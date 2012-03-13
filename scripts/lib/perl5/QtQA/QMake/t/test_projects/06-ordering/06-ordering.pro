TEMPLATE=app
TARGET=myapp
SOURCES=main.cpp
QT=core gui network xmlpatterns

# We set QT_NAMESPACE here.
# This influences DEFINES in qt.prf.
# Therefore we can later inspect the value of DEFINES to determine whether
# QtQA::QMake::Project has evaluated before or after qt.prf is loaded.
QT_NAMESPACE=QtQA_QMake_Project
