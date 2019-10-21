TEMPLATE = subdirs

qtHaveModule(widgets): SUBDIRS += bic
qtConfig(process): {
    SUBDIRS += headers
    qtHaveModule(gui): SUBDIRS += guiapplauncher
}
linux: SUBDIRS += symbols
