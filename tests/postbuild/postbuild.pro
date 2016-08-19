TEMPLATE = subdirs
SUBDIRS += \
    bic \
    headers \
    symbols \
    guiapplauncher

# This test is not valid for Windows CE
wince*: SUBDIRS -= guiapplauncher

# This test is not valid for UIKit/WinRT (no QProcess)
uikit|winrt: SUBDIRS -= headers guiapplauncher

# This test is only valid on linux
!linux: SUBDIRS -= symbols

# This test does not make sense with '-no-widgets'
!qtHaveModule(widgets): SUBDIRS -= bic
