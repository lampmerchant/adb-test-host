# ADB Test Host

A host for testing Apple Desktop Bus devices.

## HOWTO

### Requirements

* PIC
   * Microchip MPASM (bundled with MPLAB)
      * Note that you **must** use MPLAB X version 5.35 or earlier or MPLAB 8 as later versions of MPLAB X have removed MPASM
   * A PIC12F1840 microcontroller
   * A device to program the PIC with
* Python
   * Python 3.x
   * PySerial

### Steps

* Build the code using Microchip MPASM and download the result into a PIC12F1840.
* Connect the Tx and Rx lines to a UART on a PC.
* Run the Python code.

### Example

```
$ python3 -i testhost.py
>>> import serial
>>> serial_obj = serial.Serial(port='/dev/ttyS0', baudrate=115200, timeout=1)
>>> adb = AdbTestHost(serial_obj)
>>> # Press and release 'S' key on ADB keyboard
>>> adb.talk(2, 0)
b'\x01\x81'
```

## Serial Protocol

* Uses 8-N-1 at 115200 baud.
* User sends ADB command byte as it is to be transmitted
   * For a Listen (0bXXXX10XX) command, user follows with:
      * Payload length (1 byte, should be 2-8 but this is not enforced)
      * Payload
* Host sends the ADB command and then responds
   * Result code:
      * 0x00: Normal
      * 0x01: A device is requesting service (SRQ)
      * 0x02: ADB is stuck low by a misbehaving device
   * For a Talk (0bXXXX11XX) command, this is followed with:
      * Payload length (1 byte, should be 2-8 but this is not enforced)
      * Payload
* Break characters are interpreted as reset conditions; they do not have result codes
