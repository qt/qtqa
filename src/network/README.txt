This test is designed to verify the network capabilities of COIN VMs.

It attempts to resolve host addresses, as done in tst_QDnsLoopup::lookup().
In order to deliver a reliable result, it has to be built against a released
version of Qt, that has no known issues in the Network module of qtbase.

This version can be a minimal one. Only libQt6Core.so and libQt6Network.so
are needed. Those libraries have to be deployed or statically linked for
platforms that don't have a Qt installation by default (e.g. RHEL).

Example configure line:
configure --release --static --no-prefix --no-feature-gui --no-feature-icu

The executable has to be run before ctest.
If no arguments are passed, it will
- return 0, if the VM has network and otherwise 1
- write a summary about start/end of the test and the number of errors occurred

For diagnostic purposes, the following command line options are available:
  -v, --version                   Displays version information.
  -h, --help                      Displays help on commandline options.
  --help-all                      Displays help, including generic Qt options.
  --input-file, -i <jsonFile>     JSON input file to parse
  --timeout, --to, -t <timeout>   Overall timeout in milliseconds
  --warn-only, --wo               Just warn, exit 0 on error.
  --verbosity, -d <verbosity>     0=silent, 1=summary, 2=all errors, 3=all
                                  errors and successes
  --copy-default-file, -o <file>  Write a copy of the default file to the given
                                  path
  --show-progress, -p             Show progress
