# Install 240-MP

## On a Raspberry Pi

The following steps set up Raspberry Pi OS Lite and install 240-MP to start automatically at boot, without a desktop or a local login.

Steps 1-4 are focused on setting up a new card with Raspberry Pi OS Lite (64-Bit) and include options for writing a config.txt that will output to a CRT or modern TV.  

However, if you already have Raspberry Pi OS set up and working for your TV then the specific 240-MP install steps start at step 5.

### Requirements

- A RaspberryPi
    - The [Pi 4](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/) fits in a nice sweet spot of performance + composite out and its the model I use daily so its the model I am most familiar with. It supports 1080p H264/HEVC playback well on both a CRT and over HDMI.
    - The [Pi 3B and 3B+](https://www.raspberrypi.com/products/raspberry-pi-3-model-b/) work well too with some caveats...  
        - The default configuration for Pi 3 supports smooth 1080p H264 playback at the expense of removing crop functionality.  If crop is important for your use case on a Pi 3 then you can change the video decode settings with the caveat that 1080p H264 playback will no longer be smooth (720p and below  will still work well). The [hardware testing](https://github.com/anthonycaccese/240-MP/wiki/Hardware-Testing#raspberry-pi-3b) page has details on how to make that change.
        - If you choose to boot a Pi 3/3B+ from USB mass storage instead of SD, some USB flash drives can hang during early boot. If that happens, try an SD card or a different USB drive first before assuming the 240-MP install is the issue.
    - The [Pi 5](https://www.raspberrypi.com/products/raspberry-pi-5/) also works well but I've only tested over HDMI to a modern TV. The Pi 5 doesn't have a direct composite output port and one can be added through a mod but I don't have the hardware to test that.  I've added details to the [hardware testing](https://github.com/anthonycaccese/240-MP/wiki/Hardware-Testing#raspberry-pi-5) page if you'd like to explore that as an option.
    - Full details on all models can be found on the [hardware testing](https://github.com/anthonycaccese/240-MP/wiki/Hardware-Testing) page on the wiki.  If you have a setup that is working for you and would like to help out others please add a comment to [this discussion](https://github.com/anthonycaccese/240-MP/discussions/44) so we can add it to the wiki.
- SD Card (minimum of 4GB) with RaspberryPi OS already set up
    - Note: 240-MP is only an application, it's not an OS so you will need to make sure you have an OS setup and working with the display you'd like to use. 
    - In the below steps I provide an example using Raspberry Pi OS Lite that you can use to create a fresh SD card along with configs I've tested for CRT and HDMI output.
- A keyboard to navigate
- Internet Access (either WiFi or network cable will work)

### Optional

- A CRT TV and a composite cable
    - Composite out is my recommended way to use 240-MP
    - it will also work over HDMI as well so just select the config that works for your setup in step 2 below.
    - This is the composite cable I use if you happen to have a CRT: https://www.adafruit.com/product/2881 (note: I've only tested composite on the Pi 3/4 - the Pi 5 works well over HDMI
- USB remote control
    - Keyboard input works well but if you want that experience of sitting back and playing video on a VCR then a remote will definitely help with that.
    - I use this one: https://www.amazon.com/dp/B01FVUGPE8
- USB game controller 
    - Most controllers (Xbox, PlayStation, 8BitDo, NES-style, etc.) should work out of the box: D-pad/left stick to navigate, A to select, B to go back, Start for play/pause.  
    - Controllers can be plugged in at any time, and the button mapping can be customized — see [BUILDING.md → Gamepad input](BUILDING.md#gamepad-input-inputcfg).
    - If a controller isn't detected, make sure your user is in the `input` group: `sudo usermod -aG input $USER` then reboot.

### Steps

1) Write RaspberryPi OS Lite (64-bit) to an SD Card

    I reccomend using [Raspberry Pi Imager](https://www.raspberrypi.com/software/), it handles everything from OS selection to preconfiguring networking and user set up in nice simple flow

    Here is what you should select for OS if using Raspberry Pi Imager:

    | OS > Raspberry Pi OS (other) | Raspberry Pi OS Lite (64-bit) |
    | --- | --- |
    | <img src="https://github.com/user-attachments/assets/bb9f7a47-12b7-4580-abf4-ec8ad22153ba" /> | <img src="https://github.com/user-attachments/assets/30c39fce-99f8-48c9-9ad0-2b39b52690c1" /> |

    I would also suggest filling out Hostname, User and Wifi in the customization section and enabling SSH there as it will save you from having to set those up manually later.

2) After the write is complete, reconnect the card to your PC and update your config.txt to one of the following (please make sure to choose the one that best matches your TV):

    **Option 1: For composite out on a CRT TV (NTSC)...**
    ```
    # --- Global ---
    auto_initramfs=1
    disable_splash=1
    disable_overscan=1
    dtparam=audio=on

    # Composite
    enable_tvout=1
    sdtv_mode=0      # 0 = NTSC, 2 = PAL
    sdtv_aspect=1    # 1 = 4:3

    # --- Pi 3B ---
    [pi3]

    # Drivers & Video
    dtoverlay=vc4-fkms-v3d,cma-256

    # Overclocking
    over_voltage=4
    arm_freq=1300
    core_freq=450
    sdram_freq=500

    # --- Pi 3B+ ---
    [pi3+]

    # Drivers & Video
    dtoverlay=vc4-fkms-v3d,cma-256

    # Overclocking
    over_voltage=2
    arm_freq=1500
    core_freq=500
    sdram_freq=500

    # --- Pi 4B ---
    [pi4]

    # Drivers & Video
    dtoverlay=vc4-fkms-v3d,cma-256
    dtoverlay=rpivid-v4l2

    # Overclocking
    over_voltage=2
    arm_freq=1750
    gpu_freq=600

    # --- Pi 5 ---
    [pi5]

    # Drivers & Video
    dtoverlay=vc4-kms-v3d,cma-512,composite=1
    
    # --- Global ---
    [all]
    ```

    or **Option 2: for HDMI out on a modern TV...**
    ```
    # --- Global ---
    auto_initramfs=1
    disable_splash=1
    disable_overscan=1

    # HDMI
    display_auto_detect=1
    hdmi_force_hotplug=1

    # --- Pi 3B ---
    [pi3]

    # Drivers & Video
    dtoverlay=vc4-fkms-v3d,cma-256

    # Overclocking
    over_voltage=4
    arm_freq=1300
    core_freq=450
    sdram_freq=500

    # --- Pi 3B+ ---
    [pi3+]

    # Drivers & Video
    dtoverlay=vc4-fkms-v3d,cma-256

    # Overclocking
    over_voltage=2
    arm_freq=1500
    core_freq=500
    sdram_freq=500

    # --- Pi 4B ---
    [pi4]

    # Drivers & Video
    dtoverlay=vc4-fkms-v3d,cma-256
    dtoverlay=rpivid-v4l2

    # Overclocking
    over_voltage=2
    arm_freq=1750
    gpu_freq=600

    # --- Pi 5 ---
    [pi5]

    # Drivers & Video
    dtoverlay=vc4-kms-v3d
    
    # --- Global ---
    [all]
    ```

3) Place the SD card in your Raspberry Pi and let it run through its first boot sequence

    - Raspberry Pi OS Lite does **not** boot to a desktop. On first boot you may see boot log text, a text login console, or sometimes just a blinking cursor for a bit while it finishes booting.

4) Once complete, SSH into the Pi.

    - If you set the hostname/user in Raspberry Pi Imager, SSH should usually be as simple as `ssh your-user@your-hostname.local`
    - If `.local` doesn't resolve on your network, use the Pi's IP address instead (`ssh your-user@192.168.x.x`). You can find it in your router's client list or on the Pi itself with `hostname -I`

    Console auto-login is **not** needed. The installer uses a system service running as your existing user. SSH and the optional exit-to-terminal login retain their normal authentication.

5) Clone and install over SSH:

    ```bash
    git clone https://github.com/ZePWN/240-MD.git
    cd 240-MD
    bash scripts/install.sh --source .
    ```

    Install Git first with `sudo apt-get update && sudo apt-get install -y git` if needed. The installer requires Raspberry Pi OS Trixie (Debian 13), 64-bit, an existing non-root user and `sudo` access. It installs runtime and build dependencies without recommended extras, builds the checked-out source, and enables a systemd service. Building uses one compiler job to limit memory use, can take a while, and needs free disk space. Set `TMPDIR` to a directory on disk if `/tmp` is too small; advanced users can set `CMAKE_BUILD_PARALLEL_LEVEL` to build faster. Build packages remain installed afterward but do not run as background services. The installer does not install a desktop, alter display configuration, or reboot automatically. `sudo` may ask for your password.

    By default the service uses the SSH user, or an existing valid non-root service user on reinstall; its settings and files are stored under that user's home directory. If the existing service user is root or no longer exists, the installer warns and uses the invoking user instead. To select a different existing account, specify it explicitly, for example `bash scripts/install.sh --source . --user zepwn`. To install without creating or changing the autostart service, add `--no-autostart` (an existing service is not disabled).

    Once a release is published, `bash scripts/install.sh` installs the latest release instead, verifies its checksum and skips build dependencies. A specific release can be selected with `bash scripts/install.sh v1.2.0`.

6) Run `sudo reboot`. 240-MP starts on the Pi's attached display, not in the SSH terminal. To diagnose startup use `sudo systemctl status 240mp` and `sudo journalctl -u 240mp -b`. To stop it for maintenance use `sudo systemctl stop 240mp`; start it again with `sudo systemctl start 240mp`.

The service masks the tty1 and automatic virtual-terminal login services while installed so they cannot draw over the app. The Quit menu's **Exit to Terminal** starts a password-protected tty1 login; SSH access is unaffected. Streaming services may still require their own sign-in.

### Post Install

**Modules**

- The Local Files module will be enabled by default and you can open settings to enable any other modules you would like to display.  
- Please see the [modules section](https://github.com/anthonycaccese/240-MP/wiki#modules) in the wiki for details on any additional set up that may be needed for the modules you'd like to use.

**USB and Hi-MD autoplay**

- USB storage is mounted by UDisks, typically under `/media/<service-user>/<label>`. Put `Autoplay.txt` in the disc's root with the filename of a media file in that same directory on the first line. An optional second line supplies a display title (without it, the filename is displayed):

  ```text
  Moana.mp4
  Title: Moana
  ```

- **Settings > Autoplay MD** controls whether a Hi-MD disc starts automatically when inserted. It defaults to On; Off still mounts the disc and adds its title to the main menu. Turning it On takes effect on the next insertion. Other USB storage retains its existing autoplay behavior.
- Hi-MD playback, whether automatic or selected from the menu, uses Local Files' **Resume Playback** setting (Ask, Always, or Never). As with Local Files, positions are saved after five seconds and cleared near the end. Positions are identified by file size and a SHA-256 hash of the first 64 KiB, not by the mount path or title. Identical files share a position, and files with the same size and identical first 64 KiB cannot be distinguished; playlist identity covers the playlist file, not its referenced media. Existing path-based Local Files and USB history is unchanged.
- Some Hi-MD drives need time to make the disk available. 240-MP retries failed mounts every 10 seconds while the drive remains connected.
- When Linux detects a disc in a Sony Hi-MD drive, a reading indicator appears while the filesystem is mounted and the autoplay file is checked. The drive may read the disc for some time before Linux reports it. If mounting takes over one minute or no valid autoplay target is found, the indicator shows an error briefly; mounting continues to retry.
- Avoid mounting with `sudo`: UDisks normally uses `/media/root`, which the app user cannot access. Check the mount and errors with `lsblk -o NAME,FSTYPE,LABEL,MOUNTPOINTS` and `sudo journalctl -u 240mp -b | grep UsbAutoPlay`.

**HDMI-CEC**

- Enable HDMI-CEC on the TV (Samsung calls it Anynet+). On Linux, 240-MD registers as a playback device and announces itself as the active source at startup; this may switch the TV to the Pi's HDMI input.
- The TV remote's directional, select, back and playback keys can control 240-MD when the TV forwards them over CEC. Check `sudo journalctl -u 240mp -b | grep -i cec` if the adapter cannot be opened or configured.

**CRT Ouput**

- If video playback looks like its slightly squeezed/stretched then please try these steps:
    - create an `mpv.conf` file in `~/.config/mpv`
    - in that file add a line with the following
        ```
        monitorpixelaspect=0.888889
        ```
- By default, mpv assumes your display has square pixels (a ratio of 1). But for CRT output that ratio can distort the output slightly.
- `monitorpixelaspect` tells MPV how to set the pixel aspect ratio (PAR) for your particular CRT and `0.888889` is a good starting ratio to try to address that distortion.
- If that specific ratio doesn't look as you'd like on your CRT then please feel free to tweak it to best work for your set up using a 4:3 test pattern (I recommend adding one to the local files media directory for easy access if you need it).
- For an explanation on PAR along with other values you can try for both NTSC and PAL set ups; please see [this wiki entry](https://en.wikipedia.org/wiki/Pixel_aspect_ratio#Introduction) and thank you to DVDCreep for the findings [here](https://github.com/anthonycaccese/240-MP/discussions/267) that helped work this out.

**Audio**

- If analog / composite audio is unusually quiet:** 
    - Run `amixer sset PCM 100%`
    - If that solves it and you want to keep the level across reboots, run `sudo alsactl store`
- If there is no audio at all:** 
    - ALSA's `default` device resolves to whichever sound card enumerated first and sometimes that may not be the one your audio is actually plugged into, which will result in missing audio.
    - To see the cards your Pi enumerated run `cat /proc/asound/cards` (or `aplay -l`).  The short name in brackets is the card id you'll in one of the options below.  The ids you see will also depend on which config.txt from step 2 you used. (the Pi 3 / Pi 4 run fake KMS where analog / composite audio shows up as `Headphones`, while the Pi 5 blocks run Full KMS where HDMI audio shows up as `vc4hdmi0` and `vc4hdmi1`).  Any USB audio devices you've attached will have their own entries too, so please read the ids off your own Pi vs copying from here.
    - Once you have the ID for your audio device there are two options to fix it, please pick whichever fits your setup best:
        - **Option 1: change the default at the OS level**
            - Create `/etc/asound.conf` to set the card that ALSA should treat as the default, substituting the card id you read above:

                ```
                defaults.pcm.card "your-card-id"
                defaults.ctl.card "your-card-id"
                ```
            - Every program on the Pi picks this up (not just 240-MP) so this is recommened if you want to set audio output for all applications you have running on your OS.  This works on Raspberry Pi OS Lite (the image these steps use), where plain ALSA is in charge of the `default` device.  If you are running a Desktop image instead then PipeWire typically owns `default` and you should pick your output there rather than in `/etc/asound.conf`.
        - **Option 2: change it for mpv only**
            - Create (or add to your existing) `~/.config/mpv/mpv.conf` and add a single line naming the device:
                ```
                audio-device=alsa/plughw:CARD=your-card-id,DEV=0
                ```
            - Run `mpv --audio-device=help` to see the exact device strings mpv will accept and copy the one that matches your audio output device.
    - In both options the change applies the next time playback starts and will cover every mpv instance that 240-MP launches.  Please see [ARCHITECTURE.md → How mpv flags are layered](ARCHITECTURE.md#how-mpv-flags-are-layered-the-precedence-cascade) for why audio output is left to your ALSA / mpv config rather than being set by 240-MP.

**Exit to Terminal**

- If you have the autostart service installed, the Quit dialog gains `Reboot` and `Exit to Terminal` options alongside `Power Off`. `Reboot` restarts the Pi (and 240-MP comes back up via autostart). Choosing that will drop you to a login shell on the Pi instead of powering off, and leaves autostart intact for subsequent reboots. 
- To get back into 240-MP from that shell you can do one of the following:
    1. (*Recommended*) type `sudo systemctl start 240mp` to start up 240-MP and the autostart service again
    2. type `sudo reboot` to reboot and start up the device from scratch (which will also restart the autostart service)
    3. type `240mp` which will relaunch the app unmanaged in your shell; here the Quit dialog shows the plain Yes/No menu and selecting Yes will just return you to the shell rather than powering off

### Update

**Release installs:** go to `Settings → Update`, check for updates, download, and choose Apply & Restart. Your settings will be retained. Source builds report version `dev` and do not support in-app updates.

> Installs made before in-app updates were possible need to re-run the install script **once** (just follow the steps below).  Doing that will pick up the new launcher.  There is a check on the Update screen that will let you know if that's the case for you.

**Source installs:** SSH into the Pi, stop the service, update the checkout, and re-run the installer:

```bash
sudo systemctl stop 240mp
cd ~/240-MD
git pull --ff-only
bash scripts/install.sh --source .
sudo reboot
```

For a release install, re-run `bash scripts/install.sh` without `--source` instead. The existing service user and settings are retained. Use `--no-autostart` if you do not want to install or change the service.

### Uninstall

1) If autostart is installed, disable it before removing the application:

    ```bash
    sudo systemctl disable --now 240mp.service
    sudo systemctl unmask getty@tty1.service autovt@.service
    sudo rm -f /etc/systemd/system/240mp.service /etc/systemd/system/240mp-terminal.service /usr/local/bin/240mp-stop
    sudo systemctl daemon-reload
    ```

2) Remove the application:

    ```bash
    sudo rm -rf /opt/240mp
    sudo rm /usr/local/bin/240mp
    ```

## On macOS (ARM)

If you don't have a Raspberry Pi and would like to try 240-MP, I also provide a build for macOS on Apple Silicon.  You can download a DMG archive from the latest release and run it on your mac following these steps...

### Requirements

- An Apple Silicon Mac running the latest version of macOS (it will not work on Intel based devices)
- Internet Access (either WiFi or network cable will work)

### Steps

1. Download the DMG archive from the latest release
2. Mount it and move the 240mp.app into your Applications folder
3. Make sure you have mpv installed (240-MP requires MPV for playback): `brew install mpv`
4. Double click 240-MP and it should open full screen

### Post Install

**Modules**

- The Local Files module will be enabled by default and you can open settings to enable any other modules you would like to display. 
- Please see the [modules section](https://github.com/anthonycaccese/240-MP/wiki#modules) in the wiki for details on any additional set up that may be needed for the modules you'd like to use.

### Update

**From within the app (recommended):** go to `Settings → Update`, check for updates, download, and choose Apply & Relaunch — the app will swap itself in `/Applications` and reopen on the new version. Your settings will be retained.

Or manually:
1. Download the DMG archive from the latest release
2. Mount it and move the 240mp.app into your Applications folder to overwrite your existing version. *Your existing settings will be retained and it's safe to overwrite*

### Uninstall

- Remove it just like you would any application on macOS
- Remove the configuration files in `~/Library/Application Support/240-MP/`

## On SteamOS / Linux x86_64

For **SteamOS** and other x86_64 Linux distros, 240-MP ships as an **AppImage**. mpv is bundled, so there is nothing else to install; it runs on stock SteamOS without any additional package installs.

### Requirements

- SteamOS or an x86_64 Linux machine running a graphical session: X11, or Wayland with XWayland available (the AppImage ships Qt's `xcb` platform plugin)
- Internet access

The AppImage carries its own copy of the Wayland client libraries and uses them only if the system has none, so X11-only distributions that ship no Wayland at all (e.g. Batocera and similar buildroot-based images) should be able to run it too.

### Steps

> **Note for SteamOS**: please switch to Desktop Mode for the following steps

1. Download `240-MP-linux-x86_64.AppImage` from the [latest release](https://github.com/anthonycaccese/240-mp/releases/latest).
2. In your file manager, right-click the file → **Properties → Permissions** → tick *Is executable* (or run `chmod +x` on it from terminal).
3. Double-click to launch. The Local Files module is enabled by default; open Settings to enable others (see the [modules section](https://github.com/anthonycaccese/240-MP/wiki#modules) in the wiki for details on each).

### Post Install

**Modules**

- The Local Files module will be enabled by default and you can open settings to enable any other modules you would like to display. 
- Please see the [modules section](https://github.com/anthonycaccese/240-MP/wiki#modules) in the wiki for details on any additional set up that may be needed for the modules you'd like to use.

**SteamOS Gaming Mode**

- To run 240-MP from SteamOS Gaming Mode...
- In Desktop Mode, open **Steam → Games → Add a Non-Steam Game to My Library**, click **Browse**, and select the 240-MP AppImage.
- When in Gaming Mode it will appear in your library under "Non Steam Games".
- There is a set of artwork available [here](https://github.com/anthonycaccese/240-MP/discussions/249#discussioncomment-18115953) that can be used for Gaming Mode grid display.

### Update

- **From within the app (recommended):** go to `Settings → Update`, check for updates, download, and choose Apply & Relaunch. 
- The app verifies the download, swaps the new `.AppImage` over your current one in place (keeping a `.bak` of the previous version until the new one launches cleanly). 
- In **Gaming Mode** the app needs to close after applying; so simply relaunch it from your Steam library to pick up the new version (the file path is unchanged, so your existing shortcut will still work). 
- Your settings in `~/.local/share/240-MP/` are retained.
- If the app is stored in a read-only location the in-app update can't write to then the update screen simply point you at the [Releases page](https://github.com/anthonycaccese/240-mp/releases/latest) to download and replace the `.AppImage` manually.

### Uninstall

- Delete the `.AppImage` file (and remove it from Steam if you added it as a non-Steam game)
- Remove the configuration files in `~/.local/share/240-MP/`
