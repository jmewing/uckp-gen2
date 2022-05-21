Start first, by holding reset for 30 seconds and getting into recovery mode.
Once in recovery mode, update the device to version v0.8.6 (UCKP.apq8053.v0.8.6.8cf5792.181017.0942.bin)
This allows for more space on the original install/squish.fs locations
After updating to v0.8.6, reset to factory, then reboot.
ssh into your Cloud Key.  Default Username/Password is ubnt/ubnt

wget https://raw.githubusercontent.com/jmewing/uckp-gen2/main/reinstall.sh
bash reinstall.sh
