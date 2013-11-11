#!/usr/bin/python

# S55 camera pinout:
# pin 	-   description
# 1 	- 	VDD
# 2 	- 	GND
# 3 	- 	RX (to PC-TX)
# 4 	- 	TX (to PC-RX)
# 5 	- 	CTS (10k to VDD, button to GND)
# 6 	- 	RTS (10k to VDD, button to GND)
# 7 	- 	connected but no idea
# 8- 	- 	not connected
# 

import serial
import string
import re
import sys
import getopt

# usage of script
def usage():
    print "usage:", sys.argv[0], "<filename> <device> <flash/noflash>"
    print "filename - file to store the picture"
    print "flash    - taking picture with or without flash"
    print "device   - path to serial port"

# write sth to stderr
def myprint(txt):
    sys.stderr.write(txt+"\n")

# send string
def send(txt):
    myprint("> "+txt)
    ser.write(txt+"\r")
    
# send an OK
def ok():
    send("OK")


# main()
usage()

# open future picture file, writeable
f = file(sys.argv[1],'w')

# with or without flash
if sys.argv[3]=="flash":
    withflash=1
else:
    withflash=0

# init serial line, 19200 baud
#ser = serial.Serial('/dev/ttyS0', 19200, timeout=0.1)
ser = serial.Serial(sys.argv[2], 19200, timeout=0.1)

# reset the sam
myprint("shortly pull RTS to GND now")
reminder=0
exit=0

p = re.compile("AT\^SACD=2,\"17,04,2,2,.*")
while exit==0:
    a=ser.readline()			# read from serial port
    a=a.rstrip('\r');			# remove carriage return
    if len(a)>0:
	myprint("< "+a)			# debug output
	if a=="AT&F": ok()
	if a=="ATE0": ok()
	if a=="AT+CMEE=1": ok()
	if a=="AT^SACD=1": ok()
	if a=="AT^SACD=2,\"17\"": ok()
	if a=="AT^SACD=2,\"17,00,2,IQP5 02.01\"": ok()
	if withflash==1:		# with flash
		if reminder==0:		# first "17,04,2,3"
			if a=="AT^SACD=2,\"17,04,2,3\"":
			    ok() 
			    reminder=1 
			    send("^SACD: 17,03,2")
		if a=="AT^SACD=2,\"17,03,OK\"": ok()
		if a=="AT^SACD=2,\"17,03,2,1\"": ok()
		if reminder==1:		# second "17,04,2,3"
			if a=="AT^SACD=2,\"17,04,2,3\"":
			    ok()
			    # last digit -> resolution:
			    # 1:160:120, 2:640x480
			    send("^SACD: 17,04,2,2")
		if a=="AT^SACD=2,\"17,04,OK\"":
		    ok()
		if a=="AT^SACD=2,\"17,04,2,1\"": ok()
		if p.match(a):
		    ok()
		    send("^SACD: 17,01,2,2")
		if a=="AT^SACD=2,\"17,01,OK\"":
		    ok()
		    exit=1
	else:				# without flash
		if a=="AT^SACD=2,\"17,04,2,3\"":
		    ok() 
		    send("^SACD: 17,04,2,1")
		if a=="AT^SACD=2,\"17,04,OK\"": ok()
		if a=="AT^SACD=2,\"17,04,2,1\"": ok()
		if p.match(a):
		    ok()
		    # last digit -> resolution:
		    # 1:160:120, 2:640x480
		    send("^SACD: 17,01,2,2")
		if a=="AT^SACD=2,\"17,01,OK\"":
		    ok()
		    exit=1

# first close serial port
ser.close()

# then init serial with 115200 baud
#ser = serial.Serial('/dev/ttyS0', 115200, timeout=3)
ser = serial.Serial(sys.argv[2], 115200, timeout=3)
exit=0

# acknowledge the baudrate
while exit==0:
    a=ser.readline()
    a=a.rstrip('\r');
    if len(a)>0:
	myprint("< "+a)
	if a=="AT^SADT=1,115200":
	    send("CONNECT")
	    exit=1

myprint("pull CTS to GND now until done")
exit=0
size=0

# get data / picture
while exit==0:
    a=ser.readline()
    a=a.rstrip('\r');
    if len(a)>0:
	#myprint("< "+a)	# good for use of '>'
	size+=len(a)
	myprint("read "+str(size)+" bytes")
	f.write(a)
    else:
	# no more data
	if size>0: exit=1

# close serial port
ser.close()

#close file
f.close()

myprint("done.")

