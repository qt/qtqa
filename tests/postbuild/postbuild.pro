TEMPLATE = subdirs
SUBDIRS += \
    bic \
    headers \
    symbols \
    guiapplauncher

defined(qtConfig, test) {  # true since qt 5.8
    !qtConfig(process): SUBDIRS -= headers guiapplauncher
} else {
    uikit|winrt: SUBDIRS -= headers guiapplauncher
}

# This test is only valid on linux
!linux: SUBDIRS -= symbols

# This test does not make sense with '-no-widgets'
!qtHaveModule(widgets): SUBDIRS -= bic
