# Copyright (C) 2023 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
import asyncio
import decimal
import logging
import os
import shlex
import subprocess
from typing import List, Optional, Union

import common

CONFIGURE_TIMEOUT = 10 * 60
BUILD_TIMEOUT = 30 * 60
TEST_TIMEOUT = 15 * 60


class Module:
    def __init__(self, test_files: List["TestFile"]) -> None:
        self.test_files = test_files

    @staticmethod
    async def configure(
        build_directory: str, repository_directory: str, log_directory: str
    ) -> Optional[common.Error]:
        output_file = os.path.join(log_directory, "configure.log")

        error = await common.Command.run(
            arguments=[
                # Absolute path needed because we are changing the working directory.
                os.path.abspath(os.path.join(repository_directory, "configure")),
                "-release",
                "--",
                "-DQT_BUILD_BENCHMARKS=ON",
            ],
            output_file=output_file,
            timeout=CONFIGURE_TIMEOUT,
            cwd=build_directory,
        )
        if error:
            return error
        else:
            return None

    @staticmethod
    async def build(
        build_directory: str, log_directory: str, test_file: Optional[str], logger: logging.Logger
    ) -> Union["Module", common.Error]:
        target = test_file if test_file is not None else "tests/benchmarks/install/local"

        error = await common.Command.run(
            arguments=["cmake", "--build", ".", "--target", target],
            output_file=os.path.join(log_directory, "build.log"),
            timeout=BUILD_TIMEOUT,
            cwd=build_directory,
        )
        if error:
            return error

        logger.debug("Searching for test files")
        directory = os.path.join(build_directory, "tests", "benchmarks")
        test_files = Module.find_test_files(directory=directory, logger=logger)
        if not test_files:
            return common.Error(f"Found no test files in {directory}")
        else:
            return Module(test_files)

    @staticmethod
    def find_test_files(directory: str, logger: logging.Logger) -> List["TestFile"]:
        paths = []

        def report_error(error: OSError) -> None:
            logger.error(f"Error for {error.filename} while finding test cases")

        for parent, _, names in os.walk(top=directory, onerror=report_error):
            for name in names:
                path = os.path.join(parent, name)
                if name.startswith("tst_bench_") and os.access(path, os.X_OK):
                    paths.append(path)

        return [
            TestFile(directory=directory, relative_path=os.path.relpath(path, directory))
            for path in sorted(paths)
        ]


class TestFile:
    """
    A test file that runs benchmarks. It stores the benchmark results to a file.
    """

    def __init__(self, directory: str, relative_path: str) -> None:
        self.directory = directory
        self.relative_path = relative_path

    @property
    def name(self) -> str:
        return os.path.basename(self.relative_path)

    @property
    def absolute_path(self) -> str:
        return os.path.join(self.directory, self.relative_path)

    async def run(
        self,
        command_prefix: str,
        result_file: str,
        output_file: str,
        test_function: Optional[str],
        data_tag: Optional[str],
        logger: logging.Logger,
    ) -> Union["ResultFile", "TestFileIssue"]:
        # Build the command-line.
        arguments = [self.absolute_path, "-o", f"{result_file},xml"]
        if test_function:
            if data_tag:
                arguments.append(f"{test_function}:{data_tag}")
            else:
                arguments.append(f"{test_function}")
        command = command_prefix + " " + " ".join(map(shlex.quote, arguments))

        logger.debug(f'Running command "{command}"')
        with open(output_file, "w") as f:
            process = await asyncio.create_subprocess_shell(
                cmd=command,
                stdout=f,
                stderr=subprocess.STDOUT,
            )
        try:
            await asyncio.wait_for(process.wait(), timeout=TEST_TIMEOUT)
        except asyncio.TimeoutError:
            process.terminate()
            await process.wait()
            return TestFileIssue(
                test_file=self, description=f"Test timed out after {TEST_TIMEOUT} seconds"
            )

        if not os.path.exists(result_file):
            return TestFileIssue(
                test_file=self,
                description=f"Test exited with code {process.returncode} and no result file",
            )
        else:
            return ResultFile(test_file=self, path=result_file)


class TestFileIssue:
    """
    A problem that prevented us from obtaining benchmark results.

    These should be fixed.
    """

    def __init__(self, test_file: TestFile, description: str) -> None:
        self.test_file = test_file
        self.description = description


class ResultFile:
    """
    A file that contains benchmark results.
    """

    def __init__(self, test_file: TestFile, path: str) -> None:
        self.test_file = test_file
        self.path = path


class TestFileResult:
    """
    Benchmark results obtained from a result file.
    """

    def __init__(self, test_file: TestFile, test_case_result: "TestCaseResult") -> None:
        self.test_file = test_file
        self.test_case_result = test_case_result


class TestCaseResult:
    def __init__(
        self,
        name: str,
        duration: decimal.Decimal,
        test_function_results: List["TestFunctionResult"],
    ) -> None:
        self.name = name
        self.duration = duration
        self.test_function_results = test_function_results


class TestFunctionResult:
    def __init__(
        self,
        name: str,
        benchmark_results: List["BenchmarkResult"],
        incidents: List["Incident"],
        messages: List["Message"],
    ) -> None:
        self.name = name
        self.benchmark_results = benchmark_results
        self.incidents = incidents
        self.messages = messages


class BenchmarkResult:
    def __init__(
        self, data_tag: Optional[str], metric: str, iterations: int, value: decimal.Decimal
    ) -> None:
        self.data_tag = data_tag
        self.metric = metric
        self.iterations = iterations
        self.value = value


class Incident:
    def __init__(self, incident_type: str, data_tag: Optional[str]) -> None:
        self.incident_type = incident_type
        self.data_tag = data_tag


class Message:
    def __init__(self, message_type: str, data_tag: Optional[str], description: str) -> None:
        self.message_type = message_type
        self.data_tag = data_tag
        self.description = description


class ResultFileParser:
    @staticmethod
    def parse(result_file: ResultFile) -> Union[TestFileResult, TestFileIssue]:
        test_file = result_file.test_file
        test_case_result = ResultFileParser.parse_file(result_file.path)
        match test_case_result:
            case common.Error() as error:
                return TestFileIssue(
                    test_file=test_file,
                    description=f"Test result file is invalid: {error.message}",
                )

        return TestFileResult(test_file=test_file, test_case_result=test_case_result)

    @staticmethod
    def parse_file(file: str) -> Union[TestCaseResult, common.Error]:
        element = common.XmlParser.load(file=file, tag="TestCase")
        match element:
            case common.Error() as error:
                return error

        return ResultFileParser.parse_test_case_result(element)

    @staticmethod
    def parse_test_case_result(
        element: common.XmlParser,
    ) -> Union[TestCaseResult, common.Error]:
        name = element.string_attribute("name")
        match name:
            case common.Error() as error:
                return error

        child = element.child("Duration")
        match child:
            case common.Error() as error:
                return error

        duration = child.decimal_attribute("msecs")
        match duration:
            case common.Error() as error:
                return error

        test_function_results = []
        for child in element.children("TestFunction"):
            result = ResultFileParser.parse_test_function_result(child)
            match result:
                case common.Error() as error:
                    return error

            test_function_results.append(result)

        return TestCaseResult(
            name=name, duration=duration, test_function_results=test_function_results
        )

    @staticmethod
    def parse_test_function_result(
        element: common.XmlParser,
    ) -> Union[TestFunctionResult, common.Error]:
        name = element.string_attribute("name")
        match name:
            case common.Error() as error:
                return error

        messages = []
        for child in element.children("Message"):
            message = ResultFileParser.parse_message(child)
            match message:
                case common.Error() as error:
                    return error

            messages.append(message)

        incidents = []
        for child in element.children("Incident"):
            incident = ResultFileParser.parse_incident(child)
            match incident:
                case common.Error() as error:
                    return error

            incidents.append(incident)

        benchmark_results = []
        for child in element.children("BenchmarkResult"):
            benchmark_result = ResultFileParser.parse_benchmark_result(child)
            match benchmark_result:
                case common.Error() as error:
                    return error

            benchmark_results.append(benchmark_result)

        return TestFunctionResult(
            name=name, messages=messages, incidents=incidents, benchmark_results=benchmark_results
        )

    @staticmethod
    def parse_benchmark_result(
        element: common.XmlParser,
    ) -> Union[BenchmarkResult, common.Error]:
        tag = element.string_attribute("tag")
        match tag:
            case common.Error() as error:
                return error

        data_tag = tag if tag != "" else None

        metric = element.string_attribute("metric")
        match metric:
            case common.Error() as error:
                return error

        iterations = element.integer_attribute("iterations")
        match iterations:
            case common.Error() as error:
                return error

        value = element.decimal_attribute("value")
        match value:
            case common.Error() as error:
                return error

        return BenchmarkResult(data_tag=data_tag, metric=metric, iterations=iterations, value=value)

    @staticmethod
    def parse_incident(element: common.XmlParser) -> Union[Incident, common.Error]:
        incident_type = element.string_attribute("type")
        match incident_type:
            case common.Error() as error:
                return error

        children = element.children("DataTag")
        if len(children) == 0:
            data_tag = None
        elif len(children) == 1:
            data_tag = children[0].element.text
        else:
            return common.Error("Incident has multiple DataTag children")

        return Incident(incident_type=incident_type, data_tag=data_tag)

    @staticmethod
    def parse_message(element: common.XmlParser) -> Union[Message, common.Error]:
        message_type = element.string_attribute("type")
        match message_type:
            case common.Error() as error:
                return error

        children = element.children("DataTag")
        if len(children) == 0:
            data_tag = None
        elif len(children) == 1:
            data_tag = children[0].element.text
        else:
            return common.Error("Message has multiple DataTag children")

        child = element.child("Description")
        match child:
            case common.Error() as error:
                return error

        description = child.element.text
        if description is None:
            return common.Error("Message has no text")

        return Message(message_type=message_type, data_tag=data_tag, description=description)
