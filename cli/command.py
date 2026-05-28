from cli.cli_main import build_parser, main


class CommandRunner:
    def __init__(self):
        self.parser = build_parser()

    def run_command(self, command: str):
        argv = command.split()
        main(argv)


def test_parse():
    parser = build_parser()
    parser.parse_args(["wallhaven", "page", "1,2,3"])


def test_download():
    runner = CommandRunner()
    runner.run_command("wallhaven page 1")
