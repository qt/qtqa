# Copyright (C) 2023 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
import asyncio
import decimal
import os
import subprocess
import xml.etree.ElementTree as ET
from typing import List, Optional, Union


class Error:
    """
    Base class for errors.

    It is used by several modules to define error types.
    """

    __match_args__ = ("message",)

    def __init__(self, message: str) -> None:
        self.message = message


class Command:
    @staticmethod
    async def run(
        arguments: List[str],
        output_file: Optional[str] = None,
        timeout: Optional[int] = None,
        cwd: Optional[str] = None,
    ) -> Optional[Error]:
        if output_file is None:
            process = await asyncio.create_subprocess_exec(
                *arguments,
                cwd=cwd,
            )
        elif os.path.exists(output_file):
            command = " ".join(arguments)
            return Error(f'Output file of command "{command}" exists: {output_file}')
        else:
            with open(output_file, "w") as f:
                process = await asyncio.create_subprocess_exec(
                    *arguments,
                    stdout=f,
                    stderr=subprocess.STDOUT,
                    cwd=cwd,
                )

        try:
            await asyncio.wait_for(process.wait(), timeout=timeout)
        except asyncio.TimeoutError:
            command = " ".join(arguments)
            message = f'Command "{command}" timed out after {timeout} seconds'
            if output_file:
                message += f"; output was redirected to {output_file}"
            return Error(message)

        if process.returncode != 0:
            command = " ".join(arguments)
            message = f'Command "{command} returned non-zero code {process.returncode}'
            if output_file:
                message += f"; output was redirected to {output_file}"
            return Error(message)
        else:
            return None


class XmlParser:
    def __init__(self, element: ET.Element) -> None:
        self.element = element

    @staticmethod
    def load(file: str, tag: str) -> Union["XmlParser", Error]:
        try:
            tree = ET.parse(file)
        except ET.ParseError as error:
            return Error(str(error))
        else:
            element = tree.getroot()
            if element.tag != tag:
                return Error(f"Root element should be {tag} but was {element.tag}")
            else:
                return XmlParser(element)

    def children(self, tag: str) -> List["XmlParser"]:
        return [XmlParser(element) for element in self.element.findall(tag)]

    def child(self, tag: str) -> Union["XmlParser", Error]:
        children = self.children(tag)
        if len(children) == 0:
            return Error(f"{self.element.tag} has no {tag} children")
        elif len(children) == 1:
            return children[0]
        else:
            return Error(f"{self.element.tag} has multiple {tag} children")

    def string_attribute(self, name: str) -> Union[str, Error]:
        try:
            return self.element.attrib[name]
        except KeyError:
            return Error(f"{self.element.tag} has no attribute {name}")

    def integer_attribute(self, name: str) -> Union[int, Error]:
        string = self.string_attribute(name)
        match string:
            case Error() as error:
                return error

        try:
            return int(string)
        except ValueError:
            return Error(f"Could not parse {self.element.tag}.{name} as integer: {string}")

    def decimal_attribute(self, name: str) -> Union[decimal.Decimal, Error]:
        string = self.string_attribute(name)
        match string:
            case Error() as error:
                return error
        string = string.replace(",", ".")  # QtTest uses both, depending on the version.

        try:
            return decimal.Decimal(string)
        except decimal.InvalidOperation:
            return Error(f"Could not parse {self.element.tag}.{name} as decimal: {string}")
