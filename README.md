# QNAP Fan Control Script

Advanced temperature-based fan control script for QNAP NAS devices with support for quiet hours, temperature averaging, and detailed logging.

## Features

- **Automatic Temperature-Based Control**: Dynamically adjusts fan speeds based on CPU temperature
- **Quiet Hours Mode**: Reduce fan noise during specified hours (e.g., nighttime)
- **Temperature Averaging**: Reduces fan speed fluctuations by averaging multiple CPU temperature readings
- **Dual Fan Support**: Independent control for systems with two fans
- **Manual Override**: Set fan speeds manually for testing or specific use cases
- **Detailed Logging**: View current temperatures, fan speeds, and active temperature ranges
- **Multiple Model Support**: Pre-configured profiles for various QNAP models

## Supported Models

### Fully Configured Models

- **TS-453D**: Single fan configuration with optimized thresholds
- **TS-870**: Custom dual-fan temperature curve optimized for this model
- **TS-853A**: Balanced dual-fan temperature profile  

Tested on **TS-453D**.

### Partial Support

- **TS-431+**: Uses system temperature instead of CPU temperature (requires custom threshold configuration)

## Installation

1. SSH into your QNAP NAS:
   ```bash
   ssh admin@your-nas-ip
   ```

2. Download the script:
   ```bash
   wget https://raw.githubusercontent.com/D0m3L/QNAP_fanControl_bash/refs/heads/main/fancontrol-qnap.sh
   ```

3. Make it executable:
   ```bash
   chmod +x fancontrol-qnap.sh
   ```

## Usage

### Automatic Mode

Run the script to start automatic temperature-based fan control:

```bash
./fancontrol-qnap.sh
```

The script will display temperature thresholds at startup:
```
[2026-02-09 14:17:08] Starting automatic fan control for TS-453D (Manual mode: ./fancontrol-qnap.sh [1-7])
[2026-02-09 14:17:08] === Temperature Thresholds Configured ===
[2026-02-09 14:17:08]   <30°C -> Fan1 Mode 1 (~430 RPM)
[2026-02-09 14:17:08]   30-34°C -> Fan1 Mode 2 (~560 RPM)
[2026-02-09 14:17:08]   34-37°C -> Fan1 Mode 3 (~670 RPM)
[2026-02-09 14:17:08]   37-40°C -> Fan1 Mode 4 (~750 RPM)
[2026-02-09 14:17:08]   40-42°C -> Fan1 Mode 5 (~840 RPM)
[2026-02-09 14:17:08]   42-47°C -> Fan1 Mode 6 (~1050 RPM)
[2026-02-09 14:17:08]   >47°C -> Fan1 Mode 7 (~1260 RPM)
[2026-02-09 14:17:08] ==========================================
```

During operation, you'll see logs like:
```
[2026-02-09 14:17:12] CPU=45C (Range 6: 42-47°C), SYS=28C, HDD1=30C HDD2=31C HDD3=31C HDD4=31C | Fan1=1054 RPM
[2026-02-09 14:17:28] Set Fan1 to Mode 6 (~1050 RPM)
```

*Note: The Range number in the runtime logs corresponds to the Fan Mode being used.*

### Manual Mode

Set a specific fan speed (1-7):

```bash
./fancontrol-qnap.sh 3
```

**Fan Speed Reference:**
| Mode | RPM   | Use Case              |
|------|-------|-----------------------|
| 1    | ~430  | Very quiet, low temps |
| 2    | ~560  | Quiet operation       |
| 3    | ~670  | Balanced              |
| 4    | ~750  | Moderate cooling      |
| 5    | ~840  | Enhanced cooling      |
| 6    | ~1050 | High cooling          |
| 7    | ~1260 | Maximum cooling       |

### Run at Startup

To start the script automatically on boot:

1. Add to crontab:
   ```bash
   crontab -e
   ```

2. Add this line:
   ```
   @reboot /path/to/fancontrol-qnap.sh > /var/log/fan_control.log 2>&1 &
   ```

## Configuration

Edit the script to customize these settings:

```bash
# Quiet Hours
QUIET_HOURS_ENABLED=1      # 1=enabled, 0=disabled
QUIET_HOURS_START=22       # Start hour (22 = 10:00 PM)
QUIET_HOURS_END=8          # End hour (8 = 8:00 AM)
QUIET_HOURS_MAX_MODE=4     # Maximum fan mode during quiet hours

# Logging
DEBUG_MODE=1               # 1=log every loop, 0=only log changes

# Temperature Sampling
CPU_TEMP_SAMPLES=5         # Number of readings to average (1-10)
```

### Customizing Temperature Curves

For advanced users, you can modify the temperature thresholds for your model. Here are the current configurations:

**TS-453D (Single Fan):**
```bash
cpuStepTemp=( 30 34 37 40 42 47 50 )  # Temperature thresholds in °C
cpuStepFan1=( 1  2  3  4  5  6  7 )   # Fan 1 modes
```

**TS-870 (Dual Fan):**
```bash
cpuStepTemp=( 43 45 47 49 51 54 58 )  # Temperature thresholds in °C
cpuStepFan1=( 1 2 2 3 4 4 7 )         # Fan 1 modes
cpuStepFan2=( 2 2 3 4 5 6 7 )         # Fan 2 modes
```

**TS-853A (Dual Fan):**
```bash
cpuStepTemp=( 30 32 34 38 40 42 44 )  # Temperature thresholds in °C
cpuStepFan1=( 1 2 3 4 5 6 7 )         # Fan 1 modes
cpuStepFan2=( 1 2 3 4 5 6 7 )         # Fan 2 modes (same as Fan 1)
```

**Adding Support for New Models:**

To add your model, insert a new configuration block in the script:
```bash
elif [ "$sysModel" = "YOUR-MODEL" ]; then
    enableFanControl=1
    cpuStepTemp=( 30 35 40 45 50 55 60 )  # Adjust these values
    cpuStepFan1=( 1 2 3 4 5 6 7 )         # Fan modes for each range
    # cpuStepFan2=( ... )                 # Add if dual fan system
fi
```

## How It Works

1. **Temperature Monitoring**: Reads CPU, system, and HDD temperatures every 15 seconds
2. **Averaging**: Takes multiple CPU temperature samples to prevent rapid fan speed changes
3. **Range Detection**: Determines which temperature range the CPU is currently in
4. **Quiet Hours**: If enabled and within quiet hours, limits maximum fan speed
5. **Fan Adjustment**: Only changes fan speeds when crossing temperature thresholds
6. **Logging**: Records all temperature data and fan speed changes with timestamps

## Troubleshooting

### Script doesn't run
- Ensure you have root/admin access
- Check file permissions: `ls -l fancontrol-qnap.sh`
- Verify bash is available: `which sh`

### Fans not responding
- Check that your model is supported
- Try manual mode first: `./fancontrol-qnap.sh 3`
- Verify QNAP commands work: `getsysinfo cputmp`

### Temperature readings seem wrong
- Increase `CPU_TEMP_SAMPLES` for more stable readings
- Check actual temperatures: `getsysinfo cputmp`
- Verify HDD temps: `getsysinfo hdtmp 1`

## Safety Features

- **Thermal Protection**: Script will increase fan speed as temperature rises
- **Maximum Speed Override**: Fans go to maximum (Mode 7) above highest threshold
- **No Minimum Restriction**: During quiet hours, only maximum speed is limited
- **Graceful Degradation**: If script fails, QNAP's default fan control takes over

## License

MIT License - feel free to modify and distribute

## Credits

Based on the original work by [edddeduck](https://github.com/edddeduck/QNAP_Fan_Control)

## Disclaimer

This script modifies fan control behavior. While designed to be safe, use at your own risk. Monitor your NAS temperatures when first implementing to ensure adequate cooling.
