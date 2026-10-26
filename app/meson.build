# Modified for Anmir; see NOTICE for downstream changes.
src = [
    'src/main.c',
    'src/adb/adb.c',
    'src/adb/adb_device.c',
    'src/adb/adb_parser.c',
    'src/adb/adb_tunnel.c',
    'src/audio_player.c',
    'src/audio_regulator.c',
    'src/cli.c',
    'src/clipboard.c',
    'src/clock.c',
    'src/compat.c',
    'src/control_msg.c',
    'src/controller.c',
    'src/decoder.c',
    'src/demuxer.c',
    'src/device_info.c',
    'src/device_msg.c',
    'src/disconnect.c',
    'src/emulator_ui.c',
    'src/events.c',
    'src/file_pusher.c',
    'src/fps_counter.c',
    'src/frame_buffer.c',
    'src/icon.c',
    'src/input_manager.c',
    'src/keyboard_sdk.c',
    'src/mouse_capture.c',
    'src/mouse_sdk.c',
    'src/opengl.c',
    'src/options.c',
    'src/packet_merger.c',
    'src/receiver.c',
    'src/recorder.c',
    'src/recording_manager.c',
    'src/recording_save.c',
    'src/scrcpy.c',
    'src/screen.c',
    'src/sdl_hints.c',
    'src/server.c',
    'src/texture.c',
    'src/toolbar.c',
    'src/toolbar_preferences.c',
    'src/version.c',
    'src/video_regulator.c',
    'src/hid/hid_gamepad.c',
    'src/hid/hid_keyboard.c',
    'src/hid/hid_mouse.c',
    'src/trait/frame_source.c',
    'src/trait/packet_source.c',
    'src/uhid/gamepad_uhid.c',
    'src/uhid/keyboard_uhid.c',
    'src/uhid/mouse_uhid.c',
    'src/uhid/uhid_output.c',
    'src/util/acksync.c',
    'src/util/audiobuf.c',
    'src/util/average.c',
    'src/util/env.c',
    'src/util/file.c',
    'src/util/intmap.c',
    'src/util/intr.c',
    'src/util/log.c',
    'src/util/memory.c',
    'src/util/net.c',
    'src/util/net_intr.c',
    'src/util/process.c',
    'src/util/process_intr.c',
    'src/util/rand.c',
    'src/util/sdl.c',
    'src/util/strbuf.c',
    'src/util/str.c',
    'src/util/term.c',
    'src/util/thread.c',
    'src/util/tick.c',
    'src/util/timeout.c',
]

if host_machine.system() == 'darwin'
    src += [
        'src/sys/macos/clipboard_writer.m',
        'src/sys/macos/device_picker.m',
        'src/sys/macos/device_pairing.m',
        'src/sys/macos/device_connection.m',
        'src/sys/macos/device_support.m',
        'src/sys/macos/device_ui.m',
        'src/sys/macos/device_wifi.m', 'src/sys/macos/device_relay.m', 'src/sys/macos/device_reconnect.m',
        'src/sys/macos/file.m',
        'src/sys/macos/mirror_session.m',
        'src/sys/macos/theme.m',
        'src/sys/macos/localization.m',
        'src/sys/macos/settings.m',
        'src/sys/macos/application_lifecycle.m',
        'src/sys/macos/settings_window.m',
        'src/sys/macos/settings_ui.m',
        'src/sys/macos/about_window.m',
        'src/sys/macos/updater.m',
        'src/sys/macos/theme_chooser.m',
        'src/sys/macos/window_ui.m',
    ]
else
    src += [
        'src/clipboard_writer.c',
        'src/window_ui.c',
        'src/theme.c',
        'src/localization.c',
    ]
    if host_machine.system() == 'windows'
        src += 'src/sys/win/window_ui_menu.c'
    else
        src += 'src/sys/unix/window_ui_menu.c'
    endif
endif

feature_test_macros = [
    '-D_GNU_SOURCE',
    '-D_POSIX_C_SOURCE=200809L',
    '-D_XOPEN_SOURCE=700',
]

conf = configuration_data()

if host_machine.system() == 'windows'
    windows = import('windows')
    src += [
        'src/util/command.c',
        'src/sys/win/file.c',
        'src/sys/win/process.c',
        windows.compile_resources('scrcpy-windows.rc'),
    ]
    feature_test_macros += [
        '-D_WIN32_WINNT=0x0600',
        '-DWINVER=0x0600',
    ]
else
    src += [
        'src/sys/unix/file.c',
        'src/sys/unix/process.c',
    ]
    if host_machine.system() == 'darwin'
        feature_test_macros += '-D_DARWIN_C_SOURCE'
    endif
endif


add_project_arguments(feature_test_macros, language: 'c')

v4l2_support = get_option('v4l2') and host_machine.system() == 'linux'
if v4l2_support
    src += [ 'src/v4l2_sink.c' ]
endif

usb_support = get_option('usb')
if usb_support
    src += [
        'src/usb/aoa_hid.c',
        'src/usb/gamepad_aoa.c',
        'src/usb/keyboard_aoa.c',
        'src/usb/mouse_aoa.c',
        'src/usb/scrcpy_otg.c',
        'src/usb/usb.c',
    ]
endif

cc = meson.get_compiler('c')

static = get_option('static')

dependencies = [
    dependency('libavformat', version: '>= 60.3', static: static),
    dependency('libavcodec', version: '>= 60.3', static: static),
    dependency('libavutil', version: '>= 58.2', static: static),
    dependency('libswresample', static: static),
    dependency('sdl3', version: '>= 3.4.0', static: static),
]

if host_machine.system() == 'darwin'
    dependencies += dependency('appleframeworks', modules: ['AppKit', 'CoreImage', 'CoreGraphics'])
endif

if v4l2_support
    dependencies += dependency('libavdevice', static: static)
endif

if usb_support
    dependencies += dependency('libusb-1.0', static: static)
endif

if host_machine.system() == 'windows'
    dependencies += cc.find_library('mingw32')
    dependencies += cc.find_library('user32')
    dependencies += cc.find_library('ws2_32')
endif

check_functions = [
    'strdup',
    'asprintf',
    'vasprintf',
    'nrand48',
    'jrand48',
    'reallocarray',
]

foreach f : check_functions
  if cc.has_function(f)
    define = 'HAVE_' + f.underscorify().to_upper()
    conf.set(define, true)
  endif
endforeach

conf.set('HAVE_SOCK_CLOEXEC', host_machine.system() != 'windows' and
                              cc.has_header_symbol('sys/socket.h', 'SOCK_CLOEXEC'))

# the version, updated on release
conf.set_quoted('SCRCPY_VERSION', meson.project_version())

# the prefix used during configuration (meson --prefix=PREFIX)
conf.set_quoted('PREFIX', get_option('prefix'))

# build a "portable" version (with scrcpy-server accessible from the same
# directory as the executable)
conf.set('PORTABLE', get_option('portable'))

# the default client TCP port range for the "adb reverse" tunnel
# overridden by option --port
conf.set('DEFAULT_LOCAL_PORT_RANGE_FIRST', '27183')
conf.set('DEFAULT_LOCAL_PORT_RANGE_LAST', '27199')

# run a server debugger and wait for a client to be attached
conf.set('SERVER_DEBUGGER', get_option('server_debugger'))

# enable V4L2 support (linux only)
conf.set('HAVE_V4L2', v4l2_support)

# enable HID over AOA support (linux only)
conf.set('HAVE_USB', usb_support)

configure_file(configuration: conf, output: 'config.h')

src_dir = include_directories('src')

executable('anmir', src,
           dependencies: dependencies,
           include_directories: src_dir,
           install: true,
           c_args: [])

# <https://mesonbuild.com/Builtin-options.html#directories>
datadir = get_option('datadir') # by default 'share'

install_man('anmir.1')

# Native bundles copy these directories into Contents/Resources.
install_subdir('data/locales', install_dir: datadir / 'anmir')
install_data('data/scrcpy.png',
             install_dir: datadir / 'icons/hicolor/256x256/apps',
             rename: 'anmir.png')
install_data('data/scrcpy.png', install_dir: datadir / 'anmir')
install_data('data/disconnected.png',
             install_dir: datadir / 'anmir')
toolbar_icon_dir = datadir / 'anmir/toolbar-icons'
install_data(
    'data/toolbar-icons/home-20.png',
    'data/toolbar-icons/home-40.png',
    'data/toolbar-icons/home-60.png',
    'data/toolbar-icons/back-20.png',
    'data/toolbar-icons/back-40.png',
    'data/toolbar-icons/back-60.png',
    'data/toolbar-icons/screenshot-20.png',
    'data/toolbar-icons/screenshot-40.png',
    'data/toolbar-icons/screenshot-60.png',
    'data/toolbar-icons/record-20.png',
    'data/toolbar-icons/record-40.png',
    'data/toolbar-icons/record-60.png',
    'data/toolbar-icons/check-20.png',
    'data/toolbar-icons/check-40.png',
    'data/toolbar-icons/check-60.png',
    'data/toolbar-icons/stop-20.png',
    'data/toolbar-icons/stop-40.png',
    'data/toolbar-icons/stop-60.png',
    install_dir: toolbar_icon_dir)
install_data('data/zsh-completion/_anmir',
             install_dir: datadir / 'zsh/site-functions')
install_data('data/bash-completion/anmir',
             install_dir: datadir / 'bash-completion/completions')

# Desktop entry file for application launchers
if host_machine.system() == 'linux'
    # Install launchers alongside the upstream application.
    install_data('data/anmir.desktop',
                 install_dir: datadir / 'applications')
    install_data('data/anmir-console.desktop',
                 install_dir: datadir / 'applications')
endif


### TESTS

# do not build tests in release (assertions would not be executed at all)
if get_option('buildtype') == 'debug'
    tests = [
        ['test_adb_parser', [
            'tests/test_adb_parser.c',
            'src/adb/adb_device.c',
            'src/adb/adb_parser.c',
            'src/util/str.c',
            'src/util/strbuf.c',
        ]],
        ['test_binary', [
            'tests/test_binary.c',
        ]],
        ['test_audiobuf', [
            'tests/test_audiobuf.c',
            'src/util/audiobuf.c',
            'src/util/memory.c',
        ]],
        ['test_cli', [
            'tests/test_cli.c',
            'src/cli.c',
            'src/options.c',
            'src/util/log.c',
            'src/util/net.c',
            'src/util/str.c',
            'src/util/strbuf.c',
            'src/util/term.c',
        ]],
        ['test_command_windows', [
          'tests/test_command_windows.c',
          'src/util/command.c',
          'src/util/str.c',
          'src/util/strbuf.c',
        ]],
        ['test_control_msg_serialize', [
            'tests/test_control_msg_serialize.c',
            'src/control_msg.c',
            'src/util/str.c',
            'src/util/strbuf.c',
        ]],
        ['test_device_info', [
            'tests/test_device_info.c',
            'src/device_info.c',
        ]],
        ['test_device_msg_deserialize', [
            'tests/test_device_msg_deserialize.c',
            'src/device_msg.c',
        ]],
        ['test_orientation', [
            'tests/test_orientation.c',
            'src/options.c',
        ]],
        ['test_strbuf', [
            'tests/test_strbuf.c',
            'src/util/strbuf.c',
        ]],
        ['test_str', [
            'tests/test_str.c',
            'src/util/str.c',
            'src/util/strbuf.c',
        ]],
        ['test_toolbar', [
            'tests/test_toolbar.c',
            'src/toolbar.c',
        ]],
        ['test_vecdeque', [
            'tests/test_vecdeque.c',
            'src/util/memory.c',
        ]],
        ['test_vector', [
            'tests/test_vector.c',
        ]],
    ]

    foreach t : tests
        sources = t[1] + ['src/compat.c']
        exe = executable(t[0], sources,
                         include_directories: src_dir,
                         dependencies: dependencies,
                         c_args: ['-DSC_TEST'])
        test(t[0], exe)
    endforeach
    if host_machine.system() == 'darwin'
        about_test = executable('test_about_window',
            ['tests/test_about_window.m', 'src/sys/macos/about_window.m', 'src/sys/macos/localization.m'],
            include_directories: src_dir,
            dependencies: dependency('appleframeworks', modules: ['AppKit']),
            objc_args: ['-UNDEBUG'])
        test('test_about_window', about_test,
            args: [meson.current_source_dir() / 'data/locales', meson.current_source_dir() / 'data/scrcpy.icns'], timeout: 20)
        updater_test = executable('test_updater',
            ['tests/test_updater.m', 'src/sys/macos/updater.m'],
            include_directories: src_dir,
            dependencies: dependency('appleframeworks', modules: ['AppKit']),
            objc_args: ['-UNDEBUG', '-Wno-deprecated-declarations'])
        test('test_updater', updater_test)
        updater_automatic_test = executable('test_updater_automatic',
            ['tests/test_updater_automatic.m'],
            include_directories: src_dir,
            dependencies: dependency('appleframeworks', modules: ['AppKit']),
            objc_args: ['-UNDEBUG', '-Wno-deprecated-declarations'])
        test('test_updater_automatic', updater_automatic_test, timeout: 20)
        settings_startup_test = executable('test_settings_startup',
            ['tests/test_settings_startup.m', 'src/sys/macos/device_picker.m',
             'src/sys/macos/application_lifecycle.m',
             'src/sys/macos/settings_ui.m', 'src/sys/macos/about_window.m', 'src/sys/macos/updater.m', 'src/sys/macos/settings_window.m',
             'src/sys/macos/settings.m', 'src/sys/macos/localization.m',
             'src/sys/macos/device_ui.m', 'src/sys/macos/mirror_session.m',
             'src/sys/macos/device_wifi.m', 'src/sys/macos/device_relay.m', 'src/sys/macos/device_reconnect.m', 'src/sys/macos/device_connection.m',
             'src/sys/macos/device_support.m', 'src/sys/macos/device_pairing.m'],
            include_directories: src_dir,
            dependencies: dependencies + [dependency('appleframeworks', modules: ['AppKit', 'CoreImage', 'CoreGraphics'])],
            objc_args: ['-UNDEBUG'])
        test('test_settings_startup', settings_startup_test, timeout: 35)
        localization_test = executable('test_localization',
            ['tests/test_localization.m', 'src/sys/macos/localization.m'],
            include_directories: src_dir,
            dependencies: dependency('appleframeworks', modules: ['Foundation']),
            objc_args: ['-UNDEBUG'])
        test('test_localization', localization_test, args: [meson.current_source_dir() / 'data/locales'])
        settings_sync_test = executable('test_settings_sync',
            ['tests/test_settings_sync.m', 'src/sys/macos/settings.m', 'src/sys/macos/localization.m'],
            include_directories: src_dir,
            dependencies: dependencies + [dependency('appleframeworks', modules: ['AppKit'])],
            objc_args: ['-UNDEBUG'])
        test('test_settings_sync', settings_sync_test, args: [meson.current_source_dir() / 'data/locales'], timeout: 25)
        settings_test = executable('test_settings_window',
            ['tests/test_settings_window.m', 'src/sys/macos/settings_window.m',
             'src/sys/macos/device_ui.m', 'src/sys/macos/localization.m',
             'src/sys/macos/device_wifi.m', 'src/sys/macos/device_relay.m', 'src/sys/macos/device_reconnect.m', 'src/sys/macos/device_connection.m',
             'src/sys/macos/device_support.m', 'src/sys/macos/device_pairing.m'],
            include_directories: src_dir,
            dependencies: dependency('appleframeworks', modules: ['AppKit', 'CoreImage', 'CoreGraphics']),
            objc_args: ['-UNDEBUG'])
        test('test_settings_window', settings_test, args: [meson.current_source_dir() / 'data/locales'], timeout: 20)
        device_test = executable('test_device_support',
            ['tests/test_device_support.m', 'src/sys/macos/device_support.m'],
            include_directories: src_dir,
            dependencies: dependency('appleframeworks', modules: ['Foundation']),
            objc_args: ['-UNDEBUG'])
        test('test_device_support', device_test, timeout: 20)
        relay_test = executable('test_device_relay',
            ['tests/test_device_relay.m', 'src/sys/macos/device_relay.m',
             'src/sys/macos/device_pairing.m', 'src/sys/macos/device_support.m'],
            include_directories: src_dir,
            dependencies: dependency('appleframeworks', modules: ['AppKit', 'CoreImage', 'CoreGraphics']),
            objc_args: ['-UNDEBUG'])
        test('test_device_relay', relay_test, timeout: 20)
        reconnect_test = executable('test_device_reconnect',
            ['tests/test_device_reconnect.m', 'src/sys/macos/device_reconnect.m',
             'src/sys/macos/device_relay.m', 'src/sys/macos/device_connection.m',
             'src/sys/macos/device_pairing.m', 'src/sys/macos/device_support.m'],
            include_directories: src_dir,
            dependencies: dependency('appleframeworks', modules: ['AppKit', 'CoreImage', 'CoreGraphics']),
            objc_args: ['-UNDEBUG'])
        test('test_device_reconnect', reconnect_test, timeout: 30)
        pairing_test = executable('test_device_pairing',
            ['tests/test_device_pairing.m', 'src/sys/macos/device_pairing.m',
             'src/sys/macos/device_support.m'],
            include_directories: src_dir,
            dependencies: dependency('appleframeworks', modules: ['AppKit', 'CoreImage', 'CoreGraphics']),
            objc_args: ['-UNDEBUG'])
        test('test_device_pairing', pairing_test, timeout: 20)
        wifi_test = executable('test_device_wifi',
            ['tests/test_device_wifi.m', 'src/sys/macos/device_wifi.m', 'src/sys/macos/device_relay.m', 'src/sys/macos/device_reconnect.m',
             'src/sys/macos/device_ui.m', 'src/sys/macos/localization.m',
             'src/sys/macos/device_connection.m', 'src/sys/macos/device_pairing.m',
             'src/sys/macos/device_support.m'],
            include_directories: src_dir,
            dependencies: dependency('appleframeworks', modules: ['AppKit', 'CoreImage', 'CoreGraphics']),
            objc_args: ['-UNDEBUG'])
        test('test_device_wifi', wifi_test, args: [meson.current_source_dir() / 'data/locales'], timeout: 25)
        connection_test = executable('test_device_connection',
            ['tests/test_device_connection.m', 'src/sys/macos/device_connection.m',
             'src/sys/macos/device_pairing.m', 'src/sys/macos/device_support.m'],
            include_directories: src_dir,
            dependencies: dependency('appleframeworks', modules: ['AppKit', 'CoreImage', 'CoreGraphics']),
            objc_args: ['-UNDEBUG'])
        test('test_device_connection', connection_test, timeout: 30)
        mirror_test = executable('test_mirror_session',
            ['tests/test_mirror_session.m', 'src/sys/macos/mirror_session.m'],
            include_directories: src_dir,
            dependencies: dependency('appleframeworks', modules: ['AppKit']),
            objc_args: ['-UNDEBUG'])
        test('test_mirror_session', mirror_test, timeout: 20)
        device_ui_test = executable('test_device_ui',
            ['tests/test_device_ui.m', 'src/sys/macos/device_ui.m', 'src/sys/macos/localization.m'],
            include_directories: src_dir,
            dependencies: dependency('appleframeworks', modules: ['AppKit']),
            objc_args: ['-UNDEBUG'])
        test('test_device_ui', device_ui_test,
            args: [meson.current_source_dir() / 'data/scrcpy.icns'], timeout: 20)
        theme_chooser_test = executable('test_theme_chooser',
            ['tests/test_theme_chooser.m', 'src/sys/macos/theme_chooser.m',
             'src/sys/macos/device_ui.m', 'src/sys/macos/localization.m'],
            include_directories: src_dir,
            dependencies: dependency('appleframeworks', modules: ['AppKit']),
            objc_args: ['-UNDEBUG'])
        test('test_theme_chooser', theme_chooser_test, timeout: 20)
    endif
endif

if meson.version().version_compare('>= 0.58.0')
       devenv = environment()
       devenv.set('SCRCPY_ICON_DIR', meson.current_source_dir() / 'data')
       meson.add_devenv(devenv)
endif
