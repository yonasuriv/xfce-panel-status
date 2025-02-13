# XFCE Panel Status Indicators

This repository contains two scripts designed to be used with the XFCE panel as status indicators:

- **xfce4-panel-update.sh** – Reports the number of package updates available.
- ***-upgrade.sh** (e.g. `kali_upgrade.sh`) – Compares your currently installed Kali version against the latest release available online.

> **Note:** These scripts are tailored for Kali Linux. Ensure that your system is running Kali/debian (or adjust the scripts as needed).
>
> ![IUpdates display](https://github.com/user-attachments/assets/d1965136-95a2-4bcb-9e66-4e028648e6f7)

## Installation

1. **Place the Scripts:**
   It's highly recommended to copy the scripts (e.g. `xfce4-panel-update.sh` and `xfce4-panel-update.sh`) where the rest of the xfce4 panel plugins lies:
   ```
   /usr/share/kali-themes/
   ```
   Make sure the scripts are executable:
   ```bash
   sudo chmod 755 /usr/share/kali-themes/<script_name>.sh
   ```
## Configuration in XFCE Panel

To add these scripts as panel indicators in XFCE, follow these steps:

1. **Open Panel Preferences:**
   - Right-click on the XFCE panel.
   - Select **Panel → Panel Preferences**.

2. **Add a Generic Monitor:**
   - Go to the **Items** tab.
   - Click **Add** and select **Generic Monitor**.
   - Repeat this step for each script you wish to add.

3. **Configure Each Generic Monitor:**
   - In the **Command** field, enter:
     ```
     /usr/share/kali-themes/<script_name>.sh
     ```
     Replace `<script_name>.sh` with `xfce4-panel-update.sh` for the updates indicator or `kali_upgrade.sh` (or your chosen upgrade script name) for the upgrade indicator.
   - Uncheck the **Label** box so that only the output from the script is displayed.
   - Set the **Period(s)** value to `86400` (which is the number of seconds in 24 hours) to run the script once per day. This prevents excessive system usage.

4. **Apply and Close:**
   - Save your changes and close the Panel Preferences window.

## Usage

- **Updates Indicator (xfce4-panel-update.sh):**
  - Displays the number of package updates available if there are any.
  
- **Upgrade Indicator (kali_upgrade.sh):**
  - Displays a message if the latest release available on the Kali website differs from your currently installed version.
  
If any error occurs or if no updates/upgrade is needed, the script outputs nothing (or in some cases “?” to indicate an error).

## Troubleshooting

- **No Output Displayed:**  
  Verify that the scripts are executable and that the command paths are correct.
  
- **sudo Issues:**  
  If your updates script isn’t updating properly, check your sudoers configuration to ensure that the apt-get update command can run without a password prompt.

- **Parsing Errors:**  
  The upgrade script depends on the HTML layout of the Kali download page. If the page layout changes, you may need to adjust the grep/sed/awk commands used to extract the version number.

## License

This project is released under the MIT License.

---

Happy monitoring!
