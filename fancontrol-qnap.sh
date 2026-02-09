#!/bin/sh
# QNAP Fan Control Script - Compact Version
# Supports: TS-870, TS-431+, TS-853A, TS-453D

# Configuration
QUIET_HOURS_ENABLED=1      # 1=enabled, 0=disabled
QUIET_HOURS_START=22       # Start hour (0-23)
QUIET_HOURS_END=8          # End hour (0-23)
QUIET_HOURS_MAX_MODE=4     # Maximum fan mode during quiet hours (1-7)
DEBUG_MODE=1               # 1=verbose output every loop, 0=only log fan speed changes
CPU_TEMP_SAMPLES=5         # Number of temperature readings to average (1-10)

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

# Manual fan speed mode
if [ $# -eq 1 ]; then
    MANUAL_SPEED=$1
    if ! [[ "$MANUAL_SPEED" =~ ^[1-7]$ ]]; then
        log "ERROR: Fan speed must be 1-7"
        echo "Usage: $0 [1-7] | RPM: 1=~430, 2=~560, 3=~670, 4=~750, 5=~840, 6=~1050, 7=~1260"
        exit 1
    fi

    fanNum=$(getsysinfo sysfannum | awk '{print $1;}')

    case $MANUAL_SPEED in
        1) RPM="~430" ;; 2) RPM="~560" ;; 3) RPM="~670" ;; 4) RPM="~750" ;;
        5) RPM="~840" ;; 6) RPM="~1050" ;; 7) RPM="~1260" ;;
    esac

    log "Setting fans to Mode $MANUAL_SPEED (Expected: $RPM RPM)"
    hal_app --se_sys_set_fan_mode enc_sys_id=root,obj_index=0,mode=$MANUAL_SPEED
    [ $fanNum -eq 2 ] && hal_app --se_sys_set_fan_mode enc_sys_id=root,obj_index=1,mode=$MANUAL_SPEED

    sleep 2
    fanSpeed1=$(getsysinfo sysfan 1 | awk '{print $1;}')
    [ $fanNum -eq 2 ] && fanSpeed2=$(getsysinfo sysfan 2 | awk '{print $1;}')

    log "Current Speed: Fan1=$fanSpeed1 RPM$([ $fanNum -eq 2 ] && echo ", Fan2=$fanSpeed2 RPM")"
    exit 0
fi

# Automatic temperature-based control
sysModel=$(getsysinfo model | awk '{print $1;}')
enableFanControl=0

if [ "$sysModel" = "TS-870" ]; then
    enableFanControl=1
    cpuStepTemp=( 43 45 47 49 51 54 58 )
    cpuStepFan1=( 1 2 2 3 4 4 7 )
    cpuStepFan2=( 2 2 3 4 5 6 7 )
elif [ "$sysModel" = "TS-853A" ]; then
    enableFanControl=1
    cpuStepTemp=( 30 32 34 38 40 42 44 )
    cpuStepFan1=( 1 2 3 4 5 6 7 )
    cpuStepFan2=( 1 2 3 4 5 6 7 )
elif [ "$sysModel" = "TS-453D" ]; then
    enableFanControl=1
    cpuStepTemp=( 30 34 37 40 42 49 53 )
    cpuStepFan1=( 1  2  3  4  5  6  7 )
fi

if [ $enableFanControl -eq 0 ]; then
    log "ERROR: Model $sysModel not supported. Report at: https://github.com/edddeduck/QNAP_Fan_Control/issues"
    exit 1
fi

log "Starting automatic fan control for $sysModel (Manual mode: $0 [1-7])"

# Display temperature thresholds at startup
fanNum=$(getsysinfo sysfannum | awk '{print $1;}')
log "=== Temperature Thresholds Configured ==="
for (( i=0; i<7; i++ )); do
    temp_range=""
    if [ $i -eq 0 ]; then
        temp_range="<${cpuStepTemp[0]}°C"
    elif [ $i -eq 6 ]; then
        temp_range=">${cpuStepTemp[5]}°C"
    else
        temp_range="${cpuStepTemp[$((i-1))]}-${cpuStepTemp[$i]}°C"
    fi

    if [ $fanNum -eq 2 ]; then
        log "  Range $i: $temp_range -> Fan1 Mode ${cpuStepFan1[$i]}, Fan2 Mode ${cpuStepFan2[$i]}"
    else
        log "  Range $i: $temp_range -> Fan1 Mode ${cpuStepFan1[$i]}"
    fi
done
log "=========================================="

prev_mode_index=-1  # Track previous mode to detect changes

while true; do
    hddNum=$(getsysinfo hdnum | awk '{print $1;}')

    # Read CPU temperature multiple times and calculate average
    cpuTempSum=0
    for (( i=1; i<=CPU_TEMP_SAMPLES; i++ )); do
        cpuTempReading=$(getsysinfo cputmp | awk '{print $1;}')
        cpuTempSum=$((cpuTempSum + cpuTempReading))
        [ $i -lt $CPU_TEMP_SAMPLES ] && sleep 1
    done
    cpuTemp=$((cpuTempSum / CPU_TEMP_SAMPLES))

    sysTemp=$(getsysinfo systmp | awk '{print $1;}')
    fanNum=$(getsysinfo sysfannum | awk '{print $1;}')

    [ "$sysModel" = "TS-431+" ] && cpuTemp=$sysTemp

    # Get HDD temps
    hddTempStr=""
    for (( i=1; i<=hddNum; i++ )); do
        hddTemp[$i]=$(getsysinfo hdtmp $i | awk '{print $1;}')
        hddTempStr="$hddTempStr HDD$i=${hddTemp[$i]}C"
    done

    # Get fan speeds
    fanSpeed[1]=$(getsysinfo sysfan 1 | awk '{print $1;}')
    fanSpeedStr="Fan1=${fanSpeed[1]}"
    if [ $fanNum -eq 2 ]; then
        fanSpeed[2]=$(getsysinfo sysfan 2 | awk '{print $1;}')
        fanSpeedStr="$fanSpeedStr, Fan2=${fanSpeed[2]}"
    fi

    # Determine fan mode based on CPU temp
    mode_index=0
    if [ "$cpuTemp" -lt "${cpuStepTemp[0]}" ]; then
        mode_index=0
    elif [ "$cpuTemp" -gt "${cpuStepTemp[6]}" ]; then
        mode_index=6
    else
        for (( i=0; i<6; i++ )); do
            if [ "$cpuTemp" -gt "${cpuStepTemp[$i]}" ] && [ "$cpuTemp" -le "${cpuStepTemp[$((i+1))]}" ]; then
                mode_index=$((i+1))
                break
            fi
        done
    fi

    # Determine current temperature range for display
    temp_range_display=""
    if [ $mode_index -eq 0 ]; then
        temp_range_display="<${cpuStepTemp[0]}°C"
    elif [ $mode_index -eq 6 ]; then
        temp_range_display=">${cpuStepTemp[5]}°C"
    else
        temp_range_display="${cpuStepTemp[$((mode_index-1))]}-${cpuStepTemp[$mode_index]}°C"
    fi

    # Quiet hours: limit fan mode if enabled
    quiet_hours_active=0
    if [ "$QUIET_HOURS_ENABLED" -eq 1 ]; then
        current_hour=$(date '+%H')
        if [ "$current_hour" -ge "$QUIET_HOURS_START" ] || [ "$current_hour" -lt "$QUIET_HOURS_END" ]; then
            if [ "$mode_index" -gt "$QUIET_HOURS_MAX_MODE" ]; then
                mode_index=$QUIET_HOURS_MAX_MODE
                quiet_hours_active=1
            fi
        fi
    fi

    # Check if mode changed or debug mode is enabled
    mode_changed=0
    [ "$prev_mode_index" -ne "$mode_index" ] && mode_changed=1

    # Log temperature info only in debug mode or when mode changes
    if [ "$DEBUG_MODE" -eq 1 ] || [ "$mode_changed" -eq 1 ]; then
        log "CPU=${cpuTemp}C (Range $mode_index: $temp_range_display), SYS=${sysTemp}C,$hddTempStr | $fanSpeedStr RPM"
    fi

    # Set fan speeds only if mode changed
    if [ "$mode_changed" -eq 1 ]; then
        fan1_mode=${cpuStepFan1[$mode_index]}
        case $fan1_mode in
            1) RPM1="~430" ;; 2) RPM1="~560" ;; 3) RPM1="~670" ;; 4) RPM1="~750" ;;
            5) RPM1="~840" ;; 6) RPM1="~1050" ;; 7) RPM1="~1260" ;;
        esac

        hal_app --se_sys_set_fan_mode enc_sys_id=root,obj_index=0,mode=$fan1_mode

        if [ $fanNum -eq 2 ]; then
            fan2_mode=${cpuStepFan2[$mode_index]}
            case $fan2_mode in
                1) RPM2="~430" ;; 2) RPM2="~560" ;; 3) RPM2="~670" ;; 4) RPM2="~750" ;;
                5) RPM2="~840" ;; 6) RPM2="~1050" ;; 7) RPM2="~1260" ;;
            esac
            hal_app --se_sys_set_fan_mode enc_sys_id=root,obj_index=1,mode=$fan2_mode
            log "Set Fan1 to Mode $fan1_mode ($RPM1 RPM), Fan2 to Mode $fan2_mode ($RPM2 RPM)"
        else
            log "Set Fan1 to Mode $fan1_mode ($RPM1 RPM)"
        fi

        [ "$quiet_hours_active" -eq 1 ] && log "Quiet hours active ($QUIET_HOURS_START:00-$QUIET_HOURS_END:00) - limited to Mode $QUIET_HOURS_MAX_MODE"

        prev_mode_index=$mode_index
    fi

    # Sleep to complete 15 second cycle (accounting for CPU temp sampling time)
    sleep_time=$((15 - CPU_TEMP_SAMPLES + 1))
    sleep $sleep_time
done
