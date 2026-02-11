import requests
import regex
import os
import time
import json
from tqdm import tqdm
from enum import Enum
from abc import ABC, abstractmethod
from typing import Dict
from downloader.wallhaven import WallhavenDownloader


class ArgType(Enum):
    FLAG = 1
    OPTION = 2


class Argument:
    def __init__(self, name: str, required: bool, default_val: object, arg_type: ArgType):
        self._name: str = name
        self._required: bool = required
        self._default_val: object = default_val
        self._arg_type: ArgType = arg_type

    @property
    def type(self) -> ArgType:
        return self._arg_type

    @property
    def required(self) -> bool:
        return self._required

class Command(ABC):
    def __init__(self, command: str):
        self._command: str = command
        self._args: Dict[str, Argument]  = {}

    def add_option(self, name: str, argument: Argument):
        self._args[name] = argument

    def add_flag(self, name: str, argument: Argument):
        self._args[name] = argument

    def check_args(self, args: dict[str, str]):
        for arg in args.keys():
            if arg not in self._args.keys():
                raise ValueError(f"Unknown Argument: {arg}")
            if self._args[arg].type == ArgType.FLAG and args[arg] != '':
                raise ValueError(f"FLAG Argument {arg} is not expecting to have any values")
            if self._args[arg].type == ArgType.OPTION and args[arg] == '':
                raise ValueError(f"OPTION Argument {arg} is not expecting have values")
        for arg in self._args.keys():
            if self._args[arg].required and arg not in args:
                raise ValueError(f"Required Argument {arg} not supplied")

    @property
    def name(self) -> str:
        return self._command

    @abstractmethod
    def execute(self, args: dict[str, str]):
        pass

    def run(self, args: Dict[str, str]):
        self.check_args(args)
        self.execute(args)


class DownloadCommand(Command):
    def __init__(self):
        super().__init__('download')
        self.add_option(
            "page",
            Argument("page", required=True, default_val=None, arg_type=ArgType.OPTION)
        )

    def execute(self, args: Dict[str, str]):
        pages = args["page"].split(',')

        for i in range(len(pages)):
            pages[i] = int(pages[i])

        now = "wallpapers"

        dir_name = os.path.join(os.getcwd(), f"version_{now}")
        os.makedirs(dir_name, exist_ok=True)
        save_dir = os.path.join(dir_name, "my-favor0")
        os.makedirs(save_dir, exist_ok=True)
        for p in pages:
            download_page(page=p, save_dir=save_dir)


def parse(user_input: str) -> (str, Dict):
    user_input = user_input.split()
    command_name = user_input[0]
    user_input = user_input[1:]

    res = {}

    def is_arg(el: str) : return el[0] == '-'

    if not is_arg(user_input[0]):
        raise ValueError("Invalid Format: Expected an argument starting with '-', but received a non-argument value.")

    arg = None
    value = ''

    for i in user_input:
        if is_arg(i):
            if arg:
                res[arg] = value
            arg = i
            value = ''
        else:
            value += i

    res[arg] = value
    return command_name, res

class CommandRunner:
    def __init__(self):
        self._commands: Dict[str, Command] = {}

    def _parse(self, user_input: str) -> (str, Dict):
        user_input = user_input.split()
        command_name = user_input[0]
        user_input = user_input[1:]

        res = {}

        def is_arg(el: str):
            return el[0] == '-'

        if not is_arg(user_input[0]):
            raise ValueError("Invalid Format: Expected an argument starting with '-', but received a non-argument value.")

        arg = None
        value = ''

        for i in user_input:
            if is_arg(i):
                if arg:
                    res[arg[2:]] = value
                arg = i
                value = ''
            else:
                value += i

        res[arg[2:]] = value
        return command_name, res

    def register(self, command: Command):
        self._commands[command.name] = command


    def run_command(self, command: str):
        command_name, args = self._parse(command)
        if command_name not in self._commands.keys():
            raise ValueError(f"Invalid Command: {command_name}")

        self._commands[command_name].run(args)

def test_parse():
    cr = CommandRunner()
    test = 'download --page 1,2,3,4 --dir home/wp --verbose'
    print(cr._parse(test)[0])
    print(cr._parse(test)[1])


def test_download():
    cr = CommandRunner()
    cr.register(DownloadCommand())
    cr.run_command('download --page 1,2,3,4,5,6,7')

