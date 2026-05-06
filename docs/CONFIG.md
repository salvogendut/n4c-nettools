# Network Configuration (N4C.CFG)

## Overview

N4CEWENTERM and all n4c-nettools applications use a simple text configuration file to set up network parameters. This replaces the old method of hardcoding network settings in BASIC.

## Configuration File

**File name:** `N4C.CFG`  
**Location:** Same directory as the application binary on your CPC

## Format

The file contains exactly 4 lines, one value per line:

```
<IP Address>
<Netmask>
<Gateway>
<DNS Server>
```

### Example: N4C.CFG

```
192.168.1.100
255.255.255.0
192.168.1.1
192.168.1.1
```

### Line Descriptions

1. **Line 1 - IP Address:** Your CPC's IP address on the network
2. **Line 2 - Netmask:** Network subnet mask (usually 255.255.255.0 for home networks)
3. **Line 3 - Gateway:** Your router's IP address
4. **Line 4 - DNS Server:** DNS server IP (can be same as gateway, or use 8.8.8.8)

## Creating the Configuration File

### On PC

1. Create a text file named `N4C.CFG`
2. Enter your network settings (4 lines as shown above)
3. Save as plain text (ASCII)
4. Transfer to your CPC disk

### On CPC

You can create the file directly on the CPC:

```basic
10 OPENOUT "N4C.CFG"
20 PRINT #9,"192.168.1.100"
30 PRINT #9,"255.255.255.0"
40 PRINT #9,"192.168.1.1"
50 PRINT #9,"192.168.1.1"
60 CLOSEOUT
```

## Usage

When you run the terminal (or any n4c-nettools application):

1. The program loads
2. It reads `N4C.CFG` from disk
3. It configures the W5100S chip with your settings
4. It displays the configuration on screen
5. If successful, the application starts
6. If `N4C.CFG` is missing or invalid, an error is shown

## Error Messages

- **"ERROR: N4C.CFG not found"** - Create the config file on your disk
- **"ERROR: Failed to read config"** - Check file format (4 lines, valid IP addresses)
- **"ERROR: W5100S not responding"** - Check Net4CPC hardware connection

## Example Configurations

### Home Network (Router at .1)
```
192.168.1.100
255.255.255.0
192.168.1.1
192.168.1.1
```

### Home Network (Router at .254)
```
192.168.68.50
255.255.255.0
192.168.1.254
192.168.1.254
```

### Using Google DNS
```
192.168.1.100
255.255.255.0
192.168.1.1
8.8.8.8
```

### Direct Cable Connection (No Router)
```
192.168.0.2
255.255.255.0
192.168.0.1
8.8.8.8
```

## Finding Your Network Settings

On your PC (Windows):
```
ipconfig
```

On your PC (Linux/Mac):
```
ifconfig
```

Look for:
- **IP Address:** Use a free IP in the same range
- **Subnet Mask:** Copy from your PC
- **Default Gateway:** Copy from your PC
- **DNS Server:** Usually same as gateway, or use 8.8.8.8

## Tips

- Use an IP address that's not used by another device
- Keep a backup copy of your `N4C.CFG` file
- If network doesn't work, verify your settings match your network
- The same `N4C.CFG` file works for all n4c-nettools applications

## Benefits Over Old Method

✅ **Easy to change** - Edit one text file instead of BASIC code  
✅ **Portable** - Same config file for all network applications  
✅ **No BASIC editing** - No need to modify loader programs  
✅ **Clear format** - Easy to see and verify your settings  
✅ **Share configs** - Copy config files between disks easily
