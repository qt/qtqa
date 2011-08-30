This directory should contain one file per parse_build_log.pl test.

The first line of the file should be the arguments to be passed to parse_build_log.pl.
$DATADIR may be used to refer to the parent of this directory.

The rest of the file should be the expected standard output of parse_build_log.pl.

Example content of a file:

[ '--summarize', "$DATADIR/raw-logs/qtdeclarative-simple-compile-fail.txt" ]
qtdeclarative failed to compile on Linux:

  compiling qml/qdeclarativebinding.cpp
  qml/qdeclarativebinding.cpp: In static member function 'static QDeclarativeBinding* QDeclarativeBinding::createBinding(int, QObject*, QDeclarativeContext*, const QString&, int, QObject*)':
  qml/qdeclarativebinding.cpp:238: error: cannot convert 'QDeclarativeEngine*' to 'QDeclarativeEnginePrivate*' in initialization
  make[3]: *** [.obj/debug-shared/qdeclarativebinding.o] Error 1
  make[2]: *** [sub-declarative-make_default-ordered] Error 2
  make[1]: *** [module-qtdeclarative-src-make_default] Error 2
  make: *** [module-qtdeclarative] Error 2
