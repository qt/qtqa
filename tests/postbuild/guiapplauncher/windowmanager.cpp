// Copyright (C) 2017 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

#include "windowmanager.h"
#include <QtCore/QElapsedTimer>
#include <QtCore/QThread>
#include <QtCore/QDebug>
#include <QtCore/QTextStream>

#ifdef Q_WS_X11
#  include <string.h>     // memset
#  include <X11/Xlib.h>
#  include <X11/Xatom.h>  // XA_WM_STATE
#  include <X11/Xutil.h>
#  include <X11/Xmd.h>    // CARD32
#endif

#if defined(Q_OS_WIN)
#  include <qt_windows.h>
#endif

#ifdef Q_WS_X11
// X11 Window manager

// Register our own error handler to prevent the defult crashing
// behaviour. It simply counts errors in global variables that
// can be checked after calls.

static unsigned x11ErrorCount = 0;
static const char *currentX11Function = nullptr;

int xErrorHandler(Display *, XErrorEvent *e)
{
    x11ErrorCount++;

    QString msg;
    QTextStream str(&msg);
    str << "An X11 error (#" << x11ErrorCount<< ") occurred: ";
    if (currentX11Function)
        str << ' ' << currentX11Function << "()";
    str << " code: " << e->error_code;
    str.setIntegerBase(16);
    str << " resource: 0x" << e->resourceid;
    qWarning("%s", qPrintable(msg));

    return 0;
}

static bool isMapped(Display *display, Atom xa_wm_state, Window window, bool *isMapped)
{   
    Atom actual_type;
    int actual_format;
    unsigned long nitems;
    unsigned long bytes_after;
    unsigned char *prop;

    *isMapped = false;
    currentX11Function = "XGetWindowProperty";
    const int retv = XGetWindowProperty(display, window, xa_wm_state, 0L, 1L, False, xa_wm_state,
                                        &actual_type, &actual_format, &nitems, &bytes_after, &prop);

    if (retv != Success || actual_type == None || actual_type != xa_wm_state
        || nitems != 1 || actual_format != 32)
        return false;

    const CARD32 state = * reinterpret_cast<CARD32 *>(prop);

    switch ((int) state) {
    case WithdrawnState:
        *isMapped = false;
        break;
    case NormalState:
    case IconicState:
        *isMapped = true;
        break;
    default:
        *isMapped = true;
        break;
    }
    return true;
}

// Wait until a X11 top level has been mapped, courtesy of xtoolwait.
static Window waitForTopLevelMapped(Display *display, unsigned count, int timeOutMS, QString * errorMessage)
{
    unsigned mappingsCount = count;
    Atom xa_wm_state;
    XEvent event;

    // Discard all pending events
    currentX11Function = "XSync";
    XSync(display, True);

    // Listen for top level creation
    currentX11Function = "XSelectInput";
    XSelectInput(display, DefaultRootWindow(display), SubstructureNotifyMask);

    /* We assume that the window manager provides the WM_STATE property on top-level
     * windows, as required by ICCCM 2.0.
     * If the window manager has not yet completed its initialisation, the WM_STATE atom
     * might not exist, in which case we create it. */

#ifdef XA_WM_STATE    /* probably in X11R7 */
    xa_wm_state = XA_WM_STATE;
#else
    xa_wm_state = XInternAtom(display, "WM_STATE", False);
#endif

    QElapsedTimer elapsedTime;
    elapsedTime.start();
    while (mappingsCount) {
        if (elapsedTime.elapsed() > timeOutMS) {
            *errorMessage = QString::fromLatin1("X11: Timed out waiting for toplevel %1ms").arg(timeOutMS);
            return 0;
        }
        currentX11Function = "XNextEvent";
        unsigned errorCount = x11ErrorCount;
        XNextEvent(display, &event);
        if (x11ErrorCount > errorCount) {
            *errorMessage = QString::fromLatin1("X11: Error in XNextEvent");
            return 0;
        }
        switch (event.type) {
        case CreateNotify:
            // Window created, listen for its mapping now
            if (!event.xcreatewindow.send_event && !event.xcreatewindow.override_redirect)
                XSelectInput(display, event.xcreatewindow.window, PropertyChangeMask);
            break;
        case PropertyNotify:
            // Watch for map
            if (!event.xproperty.send_event && event.xproperty.atom == xa_wm_state) {
                bool mapped;                
                if (isMapped(display, xa_wm_state, event.xproperty.window, &mapped)) {
                    if (mapped && --mappingsCount == 0)
                        return event.xproperty.window;                    
                    // Past splash screen, listen for next window to be created
                    XSelectInput(display, DefaultRootWindow(display), SubstructureNotifyMask);
                } else {
                    // Some temporary window disappeared. Listen for next creation
                    XSelectInput(display, DefaultRootWindow(display), SubstructureNotifyMask);
                }
                // Main app window opened?
            }
            break;            
        default:
            break;
        }
    }
    *errorMessage = QString::fromLatin1("X11: Timed out waiting for toplevel %1ms").arg(timeOutMS);
    return 0;
}


class X11_WindowManager : public WindowManager
{
public:
    X11_WindowManager();
    ~X11_WindowManager();

protected:
    bool isDisplayOpenImpl() const override;
    bool openDisplayImpl(QString *errorMessage) override;
    QString waitForTopLevelWindowImpl(unsigned count, qint64, int timeOutMS,
                                      QString *errorMessage) override;
    bool sendCloseEventImpl(const QString &winId, qint64 pid,
                            QString *errorMessage) override;

private:
    Display *m_display;
    const QByteArray m_displayVariable;
    XErrorHandler m_oldErrorHandler;
};

X11_WindowManager::X11_WindowManager() :
    m_display(0),
    m_displayVariable(qgetenv("DISPLAY")),
    m_oldErrorHandler(0)
{
}

X11_WindowManager::~X11_WindowManager()
{
    if (m_display) {
        XSetErrorHandler(m_oldErrorHandler);
        XCloseDisplay(m_display);
    }
}

bool X11_WindowManager::isDisplayOpenImpl() const
{
    return m_display != 0;
}

bool X11_WindowManager::openDisplayImpl(QString *errorMessage)
{
    if (m_displayVariable.isEmpty()) {
        *errorMessage = QLatin1String("X11: Display not set");
        return false;
    }    
    m_display = XOpenDisplay(NULL);
    if (!m_display) {
        *errorMessage = QString::fromLatin1("X11: Cannot open display %1.").arg(QString::fromLocal8Bit(m_displayVariable));
        return false;
    }

    m_oldErrorHandler = XSetErrorHandler(xErrorHandler);
    return true;
}

QString X11_WindowManager::waitForTopLevelWindowImpl(unsigned count, qint64, int timeOutMS, QString *errorMessage)
{
    const Window w = waitForTopLevelMapped(m_display, count, timeOutMS, errorMessage);
    if (w == 0)
        return QString();
    return QLatin1String("0x") + QString::number(w, 16);
}

 bool X11_WindowManager::sendCloseEventImpl(const QString &winId, qint64, QString *errorMessage)
 {
     // Get win id
     bool ok;
     const Window window = winId.toULong(&ok, 16);
     if (!ok) {
         *errorMessage = QString::fromLatin1("Invalid win id %1.").arg(winId);
         return false;
     }
     // Send a window manager close event
     XEvent ev;
     memset(&ev, 0, sizeof (ev));
     ev.xclient.type = ClientMessage;
     ev.xclient.window = window;
     ev.xclient.message_type = XInternAtom(m_display, "WM_PROTOCOLS", true);
     ev.xclient.format = 32;
     ev.xclient.data.l[0] = XInternAtom(m_display, "WM_DELETE_WINDOW", false);
     ev.xclient.data.l[1] = CurrentTime;
     // Window disappeared or some error triggered?
     unsigned errorCount = x11ErrorCount;
     currentX11Function = "XSendEvent";
     XSendEvent(m_display, window, False, NoEventMask, &ev);
     if (x11ErrorCount > errorCount) {
         *errorMessage = QString::fromLatin1("Error sending event to win id %1.").arg(winId);
         return false;
     }
     currentX11Function = "XSync";
     errorCount = x11ErrorCount;
     XSync(m_display, False);
     if (x11ErrorCount > errorCount) {
         *errorMessage = QString::fromLatin1("Error sending event to win id %1 (XSync).").arg(winId);
         return false;
     }
     return true;
 }

#endif

#if defined(Q_OS_WIN)
// Windows

 QString winErrorMessage(unsigned long error)
{
    QString rc = QString::fromLatin1("#%1: ").arg(error);
    char16_t *lpMsgBuf;

    const int len = FormatMessage(
            FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
            NULL, error, 0, reinterpret_cast<LPTSTR>(&lpMsgBuf), 0, nullptr);
    if (len) {
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
        rc = QString::fromUtf16(lpMsgBuf, len);
#else
        rc = QString::fromUtf16(reinterpret_cast<const ushort *>(lpMsgBuf), len);
#endif
        LocalFree(lpMsgBuf);
    } else {
        rc += QString::fromLatin1("<unknown error>");
    }
    return rc;
}

 class Win_WindowManager : public WindowManager
 {
 public:
     Win_WindowManager() {}

 protected:
     bool isDisplayOpenImpl() const override;
     bool openDisplayImpl(QString *errorMessage) override;
     QString waitForTopLevelWindowImpl(unsigned count, qint64, int timeOutMS,
                                      QString *errorMessage) override;
     virtual bool sendCloseEventImpl(const QString &winId, qint64 pid,
                                     QString *errorMessage) override;

 private:
 };

bool Win_WindowManager::isDisplayOpenImpl() const
{
    return true;
}

bool Win_WindowManager::openDisplayImpl(QString *)
{
    return true;
}

// Enumerate window looking for toplevel of process id
struct FindProcessWindowEnumContext {
    FindProcessWindowEnumContext(DWORD pid) : window(0),processId(pid) {}

    HWND window;
    DWORD processId;
};

/* Check for the active main window of the Application
 * of class QWidget. */
static inline bool isQtMainWindow(HWND hwnd)
{
    static char buffer[MAX_PATH];
    if (!GetClassNameA(hwnd, buffer, MAX_PATH) || qstrncmp(buffer, "Qt", 2))
        return false;
    WINDOWINFO windowInfo;
    if (!GetWindowInfo(hwnd, &windowInfo))
        return false;
    if (!(windowInfo.dwWindowStatus & WS_ACTIVECAPTION))
        return false;
    // Check the style for a real mainwindow
    const DWORD excluded = WS_DISABLED;
    const DWORD required = WS_CAPTION | WS_SYSMENU | WS_VISIBLE;
    return (windowInfo.dwStyle & excluded) == 0
            && (windowInfo.dwStyle & required) == required;
}

static BOOL CALLBACK findProcessWindowEnumWindowProc(HWND hwnd, LPARAM lParam)
{
    DWORD processId = 0;
    FindProcessWindowEnumContext *context= reinterpret_cast<FindProcessWindowEnumContext *>(lParam);
    GetWindowThreadProcessId(hwnd, &processId);
    if (context->processId == processId && isQtMainWindow(hwnd)) {
        context->window = hwnd;
        return FALSE;
    }
    return TRUE;
}

class ScopedHandle
{
public:
    explicit ScopedHandle(HANDLE h) : m_handle(h) {}
    ~ScopedHandle() { CloseHandle(m_handle); }
    operator HANDLE() const { return m_handle; }

    ScopedHandle(const ScopedHandle &) = delete;
    ScopedHandle &operator=(const ScopedHandle &) = delete;

private:
    const HANDLE m_handle;
};

QString Win_WindowManager::waitForTopLevelWindowImpl(unsigned /* count */, qint64 pid, int timeOutMS, QString *errorMessage)
{
    const auto processId = DWORD(pid);
    const ScopedHandle hProcess(OpenProcess(PROCESS_QUERY_INFORMATION, FALSE,
                                            processId));
     if (hProcess == nullptr) {
         const int errorCode = GetLastError();
         qErrnoWarning(errorCode, "OpenProcess() failed (error %d).", errorCode);
         *errorMessage = QString::fromLatin1("OpenProcess()");
         return QString();
     }

    QElapsedTimer elapsed;
    elapsed.start();
    // First, wait until the application is up
    if (WaitForInputIdle(hProcess, timeOutMS) != 0) {
        *errorMessage = QString::fromLatin1("WaitForInputIdle time out after %1ms").arg(timeOutMS);
        return QString();
    }
    // Try to locate top level app window. App still might be in splash screen or initialization
    // phase.
    const int remainingMilliSeconds = qMax(timeOutMS - elapsed.elapsed(), qint64(500));
    const int attempts = 10;
    const int intervalMilliSeconds = remainingMilliSeconds / attempts;
    for (int a = 0; a < attempts; a++) {
        FindProcessWindowEnumContext context(processId);
        EnumWindows(findProcessWindowEnumWindowProc, reinterpret_cast<LPARAM>(&context));
        if (context.window)
            return QLatin1String("0x") + QString::number(reinterpret_cast<quintptr>(context.window), 16);
        QThread::msleep(intervalMilliSeconds);
    }
    *errorMessage = QString::fromLatin1("Unable to find toplevel of process %1 after %2ms.")
                    .arg(pid).arg(timeOutMS);
    return QString();
}

bool Win_WindowManager::sendCloseEventImpl(const QString &winId, qint64, QString *errorMessage)
{
    // Convert window back.
    quintptr winIdIntPtr;
    QTextStream str(const_cast<QString*>(&winId), QIODevice::ReadOnly);
    str.setIntegerBase(16);
    str >> winIdIntPtr;
    if (str.status() != QTextStream::Ok) {
        *errorMessage = QString::fromLatin1("Invalid win id %1.").arg(winId);
        return false;
    }
    if (!PostMessage(reinterpret_cast<HWND>(winIdIntPtr), WM_CLOSE, 0, 0)) {
        *errorMessage = QString::fromLatin1("Cannot send event to 0x%1: %2").arg(winIdIntPtr, 0, 16).arg(winErrorMessage(GetLastError()));
        return false;
    }
    return true;
}
#endif

// ------- Default implementation

WindowManager::WindowManager()
{
}

WindowManager::~WindowManager()
{
}

QSharedPointer<WindowManager> WindowManager::create()
{
#ifdef Q_WS_X11
    return QSharedPointer<WindowManager>(new X11_WindowManager);
#endif
#if defined(Q_OS_WIN) && !defined(Q_OS_WINCE)
    return QSharedPointer<WindowManager>(new Win_WindowManager);
#else
    return QSharedPointer<WindowManager>(new WindowManager);
#endif
}

static inline QString msgNoDisplayOpen() { return QLatin1String("No display opened."); }

bool WindowManager::openDisplay(QString *errorMessage)
{
    if (isDisplayOpen())
        return true;
    return openDisplayImpl(errorMessage);
}

bool WindowManager::isDisplayOpen() const
{
    return isDisplayOpenImpl();
}



QString WindowManager::waitForTopLevelWindow(unsigned count, qint64 pid, int timeOutMS, QString *errorMessage)
{
    if (!isDisplayOpen()) {
        *errorMessage = msgNoDisplayOpen();
        return QString();
    }
    return waitForTopLevelWindowImpl(count, pid, timeOutMS, errorMessage);
}

bool WindowManager::sendCloseEvent(const QString &winId, qint64 pid, QString *errorMessage)
{
    if (!isDisplayOpen()) {
        *errorMessage = msgNoDisplayOpen();
        return false;
    }
    return sendCloseEventImpl(winId, pid, errorMessage);
}

// Default Implementation
bool WindowManager::openDisplayImpl(QString *errorMessage)
{
    *errorMessage = QLatin1String("Not implemented.");
    return false;
}

bool WindowManager::isDisplayOpenImpl() const
{
    return false;
}

QString WindowManager::waitForTopLevelWindowImpl(unsigned, qint64, int, QString *errorMessage)
{
    *errorMessage = QLatin1String("Not implemented.");
    return QString();
}

bool WindowManager::sendCloseEventImpl(const QString &, qint64, QString *errorMessage)
{
    *errorMessage = QLatin1String("Not implemented.");
    return false;
}
