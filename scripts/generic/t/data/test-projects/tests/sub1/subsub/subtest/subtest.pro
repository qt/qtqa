TEMPLATE=app
CONFIG-=qt build_all debug app_bundle
CONFIG+=testcase release
win32:CONFIG+=console
SOURCES=../../../../src/fail.cpp
