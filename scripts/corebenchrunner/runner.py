# Copyright (C) 2023 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
"""
A benchmark runner that runs the benchmarks in the QtBase repository.
"""
import argparse
import asyncio
import itertools
import json
import logging
import os
import shutil
import sys
import traceback
from typing import List, Optional, Tuple, Union

import common
import coordinator
import database
import git
import host
import qt
import storage

# Name of the runner in the textual output.
OUTPUT_NAME = "runner"


class Arguments:
    """
    Command-line arguments that are parsed by the runner.
    """

    def __init__(
        self,
        configuration_file: str,
        output_directory: str,
        verbose: bool,
        overwrite: bool,
        runner_mode: "Mode",
    ) -> None:
        self.configuration_file = configuration_file
        self.output_directory = output_directory
        self.verbose = verbose
        self.overwrite = overwrite
        self.runner_mode = runner_mode

    @staticmethod
    def parse(argv: List[str]) -> "Arguments":
        parser = argparse.ArgumentParser(
            prog=OUTPUT_NAME,
            description=__doc__,
            formatter_class=argparse.RawTextHelpFormatter,
        )
        parser.add_argument(
            "--configuration",
            required=True,
            action="store",
            metavar="FILE",
            help="load configuration from FILE",
        )
        parser.add_argument(
            "--output",
            required=True,
            action="store",
            metavar="DIRECTORY",
            help="store output in DIRECTORY",
        )
        parser.add_argument(
            "--verbose",
            default=False,
            action="store_true",
            help="increase logging verbosity (will include coordinator socket activity)",
        )
        parser.add_argument(
            "--overwrite",
            default=False,
            action="store_true",
            help="overwrite the output directory if it exists",
        )
        parser.add_argument(
            "--skip-tuning",
            dest="skip_tuning",
            default=False,
            action="store_true",
            help="don't tune performance to reduce noise (disables use of root privileges)",
        )
        parser.add_argument(
            "--skip-upload",
            dest="skip_upload",
            default=False,
            action="store_true",
            help="don't upload data to the database",
        )
        parser.add_argument(
            "--skip-cleaning",
            dest="skip_cleaning",
            default=False,
            action="store_true",
            help="don't remove build directories",
        )
        parser.add_argument(
            "--single-work-item",
            default=False,
            action="store_true",
            help="run a single work item, then exit",
        )
        parser.add_argument(
            "--test-file",
            default=None,
            action="store",
            metavar="FILE",
            help="run a given test file",
        )
        parser.add_argument(
            "--test-function",
            default=None,
            action="store",
            metavar="FUNC",
            help="run a given test function",
        )
        parser.add_argument(
            "--data-tag",
            default=None,
            action="store",
            metavar="TAG",
            help="use a given data tag as input",
        )
        parser.add_argument(
            "--use-query-event",
            default=False,
            action="store_true",
            # Use a non-destructive query event to fetch work. Only useful for development.
            help=argparse.SUPPRESS,
        )
        namespace = parser.parse_args(argv)
        return Arguments(
            configuration_file=namespace.configuration,
            output_directory=namespace.output,
            verbose=namespace.verbose,
            overwrite=namespace.overwrite,
            runner_mode=Mode(
                skip_tuning=namespace.skip_tuning,
                skip_upload=namespace.skip_upload,
                skip_cleaning=namespace.skip_cleaning,
                single_work_item=namespace.single_work_item,
                test_file=namespace.test_file,
                test_function=namespace.test_function,
                data_tag=namespace.data_tag,
                use_query_event=namespace.use_query_event,
            ),
        )


class Mode:
    """
    Controls aspects of runner behavior.
    """

    def __init__(
        self,
        skip_tuning: bool,
        skip_upload: bool,
        skip_cleaning: bool,
        single_work_item: bool,
        test_file: Optional[str],
        test_function: Optional[str],
        data_tag: Optional[str],
        use_query_event: bool,
    ) -> None:
        self.skip_tuning = skip_tuning
        self.skip_upload = skip_upload
        self.skip_cleaning = skip_cleaning
        self.single_work_item = single_work_item
        self.test_file = test_file
        self.test_function = test_function
        self.data_tag = data_tag
        self.use_query_event = use_query_event


class Configuration:
    """
    Includes connection credentials for online services.
    """

    def __init__(
        self,
        coordinator_info: coordinator.Info,
        storage_mode: storage.Mode,
        git_remote: git.Remote,
    ) -> None:
        self.coordinator_info = coordinator_info
        self.storage_mode = storage_mode
        self.git_remote = git_remote

    @staticmethod
    def load(file: str, skip_upload: bool) -> Union["Configuration", common.Error]:
        """
        Load a configuration from file and validate it.
        """

        try:
            with open(file) as f:
                dictionary = json.load(f)
        except json.JSONDecodeError as decode_error:
            return common.Error(f"Failed to load configuration file: {decode_error}")

        errors = []

        # Parse coordinator information.
        coordinator_info = coordinator.Info(**dictionary["coordinator_info"])
        if not coordinator_info.url:
            errors.append("coordinator URL is empty")
        if not coordinator_info.secret:
            errors.append("coordinator secret is empty")

        # Parse the storage mode.
        if skip_upload:
            storage_mode: storage.Mode = storage.DropMode()
        else:
            storage_mode = database.Mode(**dictionary["database_info"])
            if not storage_mode.server_url:
                errors.append("database server URL is empty")
            if not storage_mode.username:
                errors.append("database username is empty")
            if not storage_mode.password:
                errors.append("database password is empty")
            if not storage_mode.database_name:
                errors.append("database name is empty")

        # Parse the Git URL.
        git_remote = git.Remote(**dictionary["qtbase_git_remote"])
        if not git_remote.url:
            errors.append("Git remote URL is empty")

        if errors:
            return common.Error("\n\t".join(["Configuration file contains errors:"] + errors))
        else:
            return Configuration(
                coordinator_info=coordinator_info, storage_mode=storage_mode, git_remote=git_remote
            )


async def main(argv: List[str]) -> int:
    arguments = Arguments.parse(argv)
    logger = create_logger(arguments.verbose)

    try:
        error = await run(arguments=arguments, logger=logger)
    except Exception:
        error = common.Error(f"Unhandled exception:\n{traceback.format_exc()}")

    if error:
        logger.critical(error.message)
        return 1
    else:
        return 0


async def run(arguments: Arguments, logger: logging.Logger) -> Optional[common.Error]:
    """
    Connect to servers and do work.
    """
    error: Optional[common.Error]

    logger.info("Loading the configuration")
    configuration = Configuration.load(
        file=arguments.configuration_file, skip_upload=arguments.runner_mode.skip_upload
    )
    match configuration:
        case common.Error() as error:
            return error

    logger.info("Creating the output directory")
    error = create_output_directory(path=arguments.output_directory, overwrite=arguments.overwrite)
    if error:
        return error

    logger.info("Gathering host information")
    host_info = await host.Info.gather()
    match host_info:
        case common.Error(message):
            return common.Error(f"Failed to gather host information: {message}")

    logger.info("Connecting to the work server")
    async with coordinator.Connection(
        coordinator_info=configuration.coordinator_info,
        hostname=host_info.name,
        logger=logger if arguments.verbose else None,
    ) as coordinator_connection:
        logger.info("Connecting to the database")
        async with configuration.storage_mode.create_environment() as storage_environment:
            logger.info("Cloning the QtBase repository")
            git_repository = await git.Repository.clone(
                remote=configuration.git_remote,
                parent_directory=arguments.output_directory,
                log_directory=arguments.output_directory,
            )
            match git_repository:
                case common.Error(message):
                    return common.Error(f"Failed to clone the Git repository: {message}")

            return await run_work_items(
                output_directory=arguments.output_directory,
                runner_mode=arguments.runner_mode,
                coordinator_connection=coordinator_connection,
                storage_environment=storage_environment,
                git_repository=git_repository,
                host_info=host_info,
                logger=logger,
            )

    return None


async def run_work_items(
    output_directory: str,
    runner_mode: Mode,
    host_info: host.Info,
    coordinator_connection: coordinator.Connection,
    storage_environment: storage.Environment,
    git_repository: git.Repository,
    logger: logging.Logger,
) -> Optional[common.Error]:
    for ordinal in itertools.count(1):
        logger.info(f"Fetching work item {ordinal}")
        work_item = await coordinator_connection.fetch_work(
            use_query_event=runner_mode.use_query_event, logger=logger
        )

        message = f"Running work item {ordinal}"
        logger.info(message)
        await coordinator_connection.send_status(
            status="new",
            message=message,
            work_item=work_item,
            logger=logger,
        )

        logger.debug("Creating directories")
        work_item_directory = os.path.join(
            output_directory, f"workitem-{ordinal}-integration-{work_item.integration_id}"
        )
        os.mkdir(work_item_directory)
        build_directory = os.path.join(work_item_directory, "build")
        os.mkdir(build_directory)
        result_directory = os.path.join(work_item_directory, "results")
        os.mkdir(result_directory)

        result = await run_work_item(
            work_item=work_item,
            work_item_directory=work_item_directory,
            build_directory=build_directory,
            result_directory=result_directory,
            runner_mode=runner_mode,
            host_info=host_info,
            coordinator_connection=coordinator_connection,
            storage_environment=storage_environment,
            git_repository=git_repository,
            logger=logger,
        )

        message = f"Done running work item {ordinal}"
        logger.info(message)
        await coordinator_connection.send_status(
            status="done",
            message=message,
            work_item=work_item,
            logger=logger,
        )

        match result:
            case common.Error() as error:
                return error

        if runner_mode.skip_cleaning:
            logger.warning("Skipping build directory removal")
        else:
            logger.info("Removing build directory")
            shutil.rmtree(build_directory)

        if runner_mode.single_work_item:
            logger.warning("Exiting after running a single work item")
            break

    return None


async def run_work_item(
    work_item: coordinator.WorkItem,
    work_item_directory: str,
    build_directory: str,
    result_directory: str,
    runner_mode: Mode,
    host_info: host.Info,
    coordinator_connection: coordinator.Connection,
    storage_environment: storage.Environment,
    git_repository: git.Repository,
    logger: logging.Logger,
) -> Optional[common.Error]:
    message = "Resetting the QtBase repository"
    logger.info(message)
    await coordinator_connection.send_status(
        status="git", message=message, work_item=work_item, logger=logger
    )
    error = await git_repository.reset(
        revision=work_item.revision,
        log_directory=work_item_directory,
    )
    if error:
        return common.Error(f"Error resetting the Git repository: {error.message}")

    message = "Configuring the QtBase module"
    logger.info(message)
    await coordinator_connection.send_status(
        status="configure", message=message, work_item=work_item, logger=logger
    )
    error = await qt.Module.configure(
        build_directory=build_directory,
        repository_directory=git_repository.directory,
        log_directory=work_item_directory,
    )
    if error:
        return common.Error(f"Error configuring QtBase: {error.message}")

    message = "Building the QtBase module"
    logger.info(message)
    await coordinator_connection.send_status(
        status="build", message=message, work_item=work_item, logger=logger
    )
    module = await qt.Module.build(
        build_directory=build_directory,
        test_file=runner_mode.test_file,
        log_directory=work_item_directory,
        logger=logger,
    )
    match module:
        case common.Error(message):
            return common.Error(f"Error building QtBase: {message}")

    if runner_mode.skip_tuning:
        result_files, run_issues = await run_test_files(
            test_files=module.test_files,
            result_directory=result_directory,
            runner_mode=runner_mode,
            work_item=work_item,
            coordinator_connection=coordinator_connection,
            logger=logger,
        )
    else:
        logger.info("Tuning performance to reduce system noise")
        error = await common.Command.run(["sudo", "prep_bench"])
        if error:
            return common.Error(f"Failed to tune performance: {error.message}")

        try:
            result_files, run_issues = await run_test_files(
                test_files=module.test_files,
                result_directory=result_directory,
                runner_mode=runner_mode,
                work_item=work_item,
                coordinator_connection=coordinator_connection,
                logger=logger,
            )
        finally:
            error = await common.Command.run(["sudo", "unprep_bench"])

        if error:
            return common.Error(f"Failed to revert performance tuning: {error.message}")

    results, parse_issues = parse_results(result_files=result_files, logger=logger)

    await coordinator_connection.send_status(
        status="results", message="Storing results", work_item=work_item, logger=logger
    )
    error = await storage_environment.store(
        results=results,
        issues=run_issues + parse_issues,
        work_item=work_item,
        host_info=host_info,
        logger=logger,
    )
    if error:
        return common.Error(f"Error storing results: {error.message}")

    return None


async def run_test_files(
    test_files: List[qt.TestFile],
    result_directory: str,
    runner_mode: Mode,
    work_item: coordinator.WorkItem,
    coordinator_connection: coordinator.Connection,
    logger: logging.Logger,
) -> Tuple[List[qt.ResultFile], List[qt.TestFileIssue]]:
    issues: List[qt.TestFileIssue] = []
    result_files: List[qt.ResultFile] = []

    logger.info("Running test files")
    if runner_mode.skip_tuning:
        logger.warning("Running without performance tuning")
        command_prefix = ""
    else:
        # Run the process in the prepared core, and with a high priority to prevent descheduling.
        command_prefix = "sudo renice -n -5 -p $$ && exec taskset -c 0"
    if runner_mode.test_file:
        logger.warning(f"Only running a given test file: {runner_mode.test_file}")
        if runner_mode.test_function:
            logger.warning(f"Only running a given test function: {runner_mode.test_function}")
            if runner_mode.data_tag:
                logger.warning(f"Only using a given data tag as input: {runner_mode.data_tag}")

    for ordinal, test_file in enumerate(test_files, start=1):
        message = f"Running test file {ordinal} of {len(test_files)}"
        logger.debug(message)
        await coordinator_connection.send_status(
            status="test",
            message=message,
            work_item=work_item,
            logger=logger,
        )

        logger.debug("Creating the output directory")
        output_directory = os.path.join(result_directory, test_file.name)
        os.mkdir(output_directory)

        outcome = await test_file.run(
            command_prefix=command_prefix,
            result_file=os.path.join(output_directory, "result.xml"),
            output_file=os.path.join(output_directory, "output.txt"),
            test_function=runner_mode.test_function,
            data_tag=runner_mode.data_tag,
            logger=logger,
        )

        match outcome:
            case qt.TestFileIssue() as issue:
                logger.warning(issue.description)
                issues.append(issue)
            case qt.ResultFile() as file:
                result_files.append(file)

        logger.debug("Done")

    return (result_files, issues)


def parse_results(
    result_files: List[qt.ResultFile], logger: logging.Logger
) -> Tuple[List[qt.TestFileResult], List[qt.TestFileIssue]]:
    results: List[qt.TestFileResult] = []
    issues: List[qt.TestFileIssue] = []

    for file in result_files:
        logger.debug(f"Parsing results from {file.path}")
        result = qt.ResultFileParser.parse(file)
        match result:
            case qt.TestFileIssue() as issue:
                logger.warning(issue.description)
                issues.append(issue)
                continue

        results.append(result)

    return results, issues


def create_logger(verbose: bool) -> logging.Logger:
    logger = logging.getLogger(OUTPUT_NAME)
    logger.setLevel(logging.DEBUG if verbose else logging.INFO)
    formatter = logging.Formatter(
        fmt="%(asctime)s %(name)s %(levelname)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    handler = logging.StreamHandler()
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    return logger


def create_output_directory(path: str, overwrite: bool) -> Optional[common.Error]:
    if not os.path.exists(path):
        os.mkdir(path)
        return None
    elif overwrite:
        shutil.rmtree(path)
        os.mkdir(path)
        return None
    else:
        return common.Error("Output directory exists (use --overwrite to remove it)")


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1:]))
