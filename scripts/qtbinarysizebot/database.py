# Copyright (C) 2024 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
""" Influx database interface wrapper module """
import datetime
import influxdb_client  # type: ignore
from influxdb_client.client.influxdb_client import InfluxDBClient  # type: ignore


class Database():
    """ Influx database interface wrapper class """
    def __init__(self, server_url: str, database_name: str, username: str, password: str):
        self.bucket = f"{database_name}/autogen"
        self.client = InfluxDBClient(
            url=server_url, token=f"{username}:{password}", org="-", debug=False
        )
        self.query_api = self.client.query_api()
        self.write_api = self.client.write_api()

    def get_last_timestamp(self) -> datetime.datetime:
        """ Fetches timestamp for last database entry """
        query = f'from(bucket:"{self.bucket}") \
            |> range(start: 0, stop: now()) \
            |> keep(columns: ["_time"]) \
            |> last(column: "_time")'
        result = self.query_api.query(query)

        if len(result) == 0:
            return None

        if len(result[0].records) > 1:
            raise IndexError(f'Too many results: {result[0]}')

        return result[0].records[0].get_time()

    def push(
            self,
            series: str,
            commit_url: str,
            coin_task_datetime: datetime.datetime,
            binary: str,
            value: int):
        # pylint: disable=R0913
        """ Pushes new entry into database series """
        point = influxdb_client.Point(series)
        point.tag("entry", binary)
        point.tag("commit_url", commit_url)
        point.field("value", value)
        point.time(coin_task_datetime)

        self.write_api.write(bucket=self.bucket, record=point)

    def pull(self, series: str, entry: str) -> float:
        """ Fetches last database entry """
        query = (f'from(bucket:"{self.bucket}") '
                 '|> range(start:0) '
                 '|> drop(columns: ["commit_url"]) '
                 f'|> filter(fn:(r) => r._measurement == "{series}" and r.entry == "{entry}") '
                 '|> sort(columns: ["_time"]) '
                 '|> last() '
                 )

        result = self.query_api.query(query)
        if len(result) == 0:
            return 0
        if len(result[0].records) > 1:
            raise IndexError('Too many results')
        return result[0].records[0].get_value()
