TEMPLATE = subdirs
SUBDIRS +=  bic headers symbols guiapplauncher compilerwarnings

# Temporarily avoid `make check' running the guiapplauncher test.
# It is a bit unstable, and we need more infrastructure to handle this.
# Task: QTQAINFRA-146
check.CONFIG         = recursive
check.recurse        = $$SUBDIRS
check.recurse       -= guiapplauncher
check.recurse_target = check
QMAKE_EXTRA_TARGETS += check
