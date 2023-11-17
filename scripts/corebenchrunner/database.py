# Copyright (C) 2023 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
import datetime
import logging
from typing import Any, Dict, List, Optional, Union

import influxdb_client  # type: ignore
from influxdb_client.client.influxdb_client_async import InfluxDBClientAsync  # type: ignore

import common
import coordinator
import host
import qt
import storage


class Mode(storage.Mode):
    """
    A storage mode in which the runner uploads results to a database.

    It includes database credentials.
    """

    def __init__(self, server_url: str, username: str, password: str, database_name: str) -> None:
        self.server_url = server_url
        self.username = username
        self.password = password
        self.database_name = database_name

    def create_environment(self) -> "Environment":
        return Environment(self)


class Environment(storage.Environment):
    """
    Uploads results to a database.
    """

    def __init__(self, mode: Mode) -> None:
        self.database_name = mode.database_name
        self.client = InfluxDBClientAsync(
            url=mode.server_url, token=f"{mode.username}:{mode.password}", org="-"
        )

    async def __aenter__(self) -> "Environment":
        await self.client.__aenter__()
        return self

    async def __aexit__(self, exception_type: Any, exception_value: Any, traceback: Any) -> bool:
        await self.client.__aexit__(exception_type, exception_value, traceback)
        return False

    async def store(
        self,
        results: List[qt.TestFileResult],
        issues: List[qt.TestFileIssue],
        work_item: coordinator.WorkItem,
        host_info: host.Info,
        logger: logging.Logger,
    ) -> Optional[common.Error]:
        logger.debug("Preparing results for upload")
        data_points = self.prepare_data(
            results=results,
            issues=issues,
            work_item=work_item,
            host_info=host_info,
            logger=logger,
        )
        match data_points:
            case common.Error() as error:
                return error

        logger.info("Uploading results")
        try:
            await self.client.write_api().write(
                bucket=f"{self.database_name}/autogen", record=data_points
            )
        except Exception as exception:
            return common.Error(f"InfluxDB exception: {repr(exception)}")

        return None

    def prepare_data(
        self,
        results: List[qt.TestFileResult],
        issues: List[qt.TestFileIssue],
        work_item: coordinator.WorkItem,
        host_info: host.Info,
        logger: logging.Logger,
    ) -> Union[List[influxdb_client.Point], common.Error]:
        """
        Prepare data for upload.

        Data points are created for several measurements. Integration timestamp is used as time.
        """
        benchmark_run = [
            self.prepare_benchmark_run(
                timestamp=work_item.integration_timestamp,
                host_info=host_info,
                work_item=work_item,
            )
        ]

        test_file_issues = self.prepare_test_file_issues(
            timestamp=work_item.integration_timestamp,
            issues=issues,
            branch=work_item.branch,
            host_info=host_info,
        )

        benchmark_results = self.prepare_benchmark_results(
            timestamp=work_item.integration_timestamp,
            branch=work_item.branch,
            results=results,
            host_info=host_info,
            logger=logger,
        )

        if not benchmark_results:
            return common.Error("No data points in test results")
        else:
            return benchmark_run + test_file_issues + benchmark_results

    def prepare_benchmark_run(
        self,
        timestamp: datetime.datetime,
        host_info: host.Info,
        work_item: coordinator.WorkItem,
    ) -> influxdb_client.Point:
        """
        Create a data point for the benchmark run measurement.
        """
        point = influxdb_client.Point("benchmark_runs")
        point.time(timestamp)
        point.tag("host", host_info.name)
        point.tag("branch", work_item.branch)
        point.field("integration_id", work_item.integration_id)
        point.field("sha", work_item.revision)
        return point

    def prepare_test_file_issues(
        self,
        timestamp: datetime.datetime,
        host_info: host.Info,
        branch: str,
        issues: List[qt.TestFileIssue],
    ) -> List[influxdb_client.Point]:
        """
        Create data points for the test file issue measurement.
        """
        points = []
        for issue in issues:
            point = influxdb_client.Point("test_file_issues")
            point.time(timestamp)
            point.tag("host", host_info.name)
            point.tag("branch", branch)
            point.tag("test_file", issue.test_file.relative_path)
            point.field("description", issue.description)
            points.append(point)
        return points

    def prepare_benchmark_results(
        self,
        timestamp: datetime.datetime,
        branch: str,
        results: List[qt.TestFileResult],
        host_info: host.Info,
        logger: logging.Logger,
    ) -> List[influxdb_client.Point]:
        """
        Create data points for the benchmark result measurement.
        """
        points = []
        for test_file_result in results:
            logger.debug(f"Preparing results from test file {test_file_result.test_file.name}")
            for test_function_result in test_file_result.test_case_result.test_function_results:
                logger.debug(f"Preparing results from test function {test_function_result.name}")

                # Group everything by data tag.
                benchmark_results_by_tag: Dict[Optional[str], List[qt.BenchmarkResult]] = {}
                for benchmark_result in test_function_result.benchmark_results:
                    benchmark_results_by_tag.setdefault(benchmark_result.data_tag, []).append(
                        benchmark_result
                    )
                incidents_by_tag: Dict[Optional[str], List[qt.Incident]] = {}
                for incident in test_function_result.incidents:
                    incidents_by_tag.setdefault(incident.data_tag, []).append(incident)
                messages_by_tag: Dict[Optional[str], List[qt.Message]] = {}
                for message in test_function_result.messages:
                    messages_by_tag.setdefault(message.data_tag, []).append(message)

                for tag, benchmark_results in benchmark_results_by_tag.items():
                    incidents = incidents_by_tag.get(benchmark_result.data_tag, [])
                    if len(benchmark_results) > 1:
                        logger.debug(
                            "Dropping benchmark result data from "
                            f"test file {test_file_result.test_file.name}, "
                            f"test function {test_function_result.name}, "
                            f'and data tag "{tag}": duplicate data tags'
                        )
                    elif not incidents:
                        logger.debug(
                            "Dropping benchmark result data from "
                            f"test file {test_file_result.test_file.name}, "
                            f"test function {test_function_result.name}, "
                            f'and data tag "{tag}": no pass/fail information'
                        )
                    else:
                        benchmark_result = benchmark_results[0]
                        incident = incidents[0]
                        point = influxdb_client.Point("benchmark_results")
                        point.time(timestamp)
                        point.tag("host", host_info.name)
                        point.tag("branch", branch)
                        point.tag("test_file", test_file_result.test_file.relative_path)
                        point.tag("test_case", test_file_result.test_case_result.name)
                        point.tag("test_function", test_function_result.name)
                        point.tag("data_tag", benchmark_result.data_tag)
                        point.field("value", benchmark_result.value)
                        points.append(point)
        return points
