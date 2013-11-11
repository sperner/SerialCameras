#!/usr/bin/perl


system("stty raw -F/dev/ttyUSB0 speed 9600");
system("stty raw -F/dev/ttyUSB0 speed 9600");
open(COM, "</dev/ttyUSB0") || die("Can't Open ttyUSB0 for reading");
open(OUT, ">/dev/ttyUSB0") || die("Can't Open ttyUSB0 for writing");
open(LOG, ">logfile") || die("cant open logfile");
open(DAT, ">data")||die("err opening data");

#make OUT and LOG hot (disable output buffering):
select((select(OUT), $|=1)[0]);
select((select(LOG), $|=1)[0]);
select((select(DAT), $|=1)[0]);


$cmd = "";
$sent = "";
$state=0;
$data = "";
$picmode = 0;
$jpeg_stream=0;

while(1==1){ #$res=getc(COM)){
	$res=getc(COM);
	$val = ord($res);
	$cmd .= $res;
	
	if (substr($cmd,0,1) ne "A"){ $cmd = ""; } 
	
	print "<$res\n";
	printf ("%02x = %c\n",$val, $val);
	
	if (($state==0 && ($res eq "\r" || $res eq "\n"))){
		#STATE=0 -> no mux enable
		chop($cmd);
		print "<<IN  <<$cmd.\n";

		if ($cmd eq "AT&F"){
			send_cmd($cmd);
			send_ok();
		}elsif ($cmd eq "AT+IPR=?"){
			send_cmd($cmd);
			#send_cmd("\r\r\n+IPR: (),(1200,2400,4800,9600,38400)\r\n\r\nOK\r\n");
			send_cmd("+IPR: (),(1200,2400,4800,9600,19200,38400,57600,460800)\r\n\r\nOK\r\n");
		}elsif ($cmd eq "AT+CMUX=?"){
			send_cmd($cmd);
			send_cmd("\r\r\n+CMUX: (0),(0),(1-7),(31),(10),(3),(30),(10),(1-7)\r"); #\n\r\nOK\r\n");

		}elsif ($cmd eq "AT+CMUX=0,0,7,31"){
			send_cmd($cmd);
			send_ok();

			# init mux state:
			$state = 1;
			
		}elsif($cmd eq "AT+IPR=460800"){ #57600"){
			send_cmd($cmd);
			send_cmd("\r\nOK\r\n");
			print "\n\nsetting RS232 speed to 460kbaud...\n";
			
			close(COM);
			close(OUT);
			
			sleep(1);
			select(undef, undef, undef, 0.2);

			system("stty raw -F/dev/ttyUSB0 speed 460800"); #57600");
			system("stty raw -F/dev/ttyUSB0 speed 460800"); #57600");
			#send_cmd("\r\r\nOK\r\n");
			open(COM, "</dev/ttyUSB0") || die("Can't Open ttyUSB0 for reading");
			open(OUT, ">/dev/ttyUSB0") || die("Can't Open ttyUSB0 for writing");
		}
	
		
		$cmd="";
	}elsif($state >0){
		#print "state=$state, cmd<$cmd>\n";
		if ($state == 1 || ($state < 3 && $res eq "\xF9")){
			# -> start command:
			$data = "";
			$state = 2;
		}elsif($state==2){
			$data .= $res; #address
			$state = 3;
		}elsif($state==3){
			$data .= $res; #control
			$state = 4;
		}elsif($state==4){
			$data .= $res; #length
			$len = ord($res)>>1;
			print "LEN=$len\n";
			$state = 5;
		}elsif($state<5+$len){
			$data .= $res; #data
			$state++;
		}elsif($state<5+$len+1){
			#checksum
			$check = $res;
			$state++;
		}else{
			#END
			print "GOT PACKET: DATA<".make_readable($data)."> [".encode($data)."](".encode($check).")\n";
			
			if ($data eq "\x03\x3F\x01"){
				# DLCI REQUEST -> SEND ACK
				# ch0: open
				send_cmd("\xF9\x03\x73\x01\xD7\xF9"); #handy: F9  03 73 01 D7  F9
				
			}elsif( $data eq "\x23\x3F\x01"){
				# open another channel -> SEND ACK
				# ch3: open
				send_cmd("\xF9\x23\x73\x01\x02\xF9"); #handy: F9 23 73  01 02 F9
				
			}elsif( $data eq "\x03\xEF\x09\xE3\x05\x23\x8D"){
				#set up mux0
				send_cmd("\xF9\x01\xEF\x0B\xE3\x07\x23\x0C\x01\x79\xF9"); 
				
			}elsif( $data eq "\x03\xEF\x09\xE1\x07\x23\x0C"){
				#set up mux3
				send_cmd("\xF9\x01\xEF\x09\xE1\x05\x23\x8D\x9A\xF9");
				
			}elsif( $data eq "\x81\x73\x01"){
				print "\n CHANNEL 1 OPEN! \n";
			
			}elsif( $data eq "\x03\xEF\x09\xE3\x05\x83\x8D"){
				#set up mux1:
				send_cmd("\xF9\x01\xEF\x09\xE1\x05\x83\x8D\x9A\xF9");

				send_ch1_data(
						"\x80\x00\x1A\x10\x00\x02".
						"\x00\x46\x00\x13\xE3\x3D\x95\x45\x83\x74".
						"\x4A\xD7\x9E\xC5\xC1\x6B\xE3\x1E\xDE\x8E\x61"
					     );
						
			}elsif( $data eq "\x83\xEF\xA0\x00\x1F\x10\x00\x20".
				         "\x00\xCB\x00\x00\x00\x01\x4A\x00\x13\xE3".
					 "\x3D\x95\x45\x83\x74\x4A\xD7\x9E\xC5\xC1".
					 "\x6B\xE3\x1E\xDE\x8E"){
				#83 EF 3F A0 00 1F 10 00 20 00 CB 00 00 00 01 4A 00
				#13 E3 3D 95 45 83 74 4A D7 9E C5 C1 6B E3 1E DE 8E
				print "\n\n\YEAH GOT CAMERA INIT ACK\n";
				sleep(10);
			
			}elsif( (substr($data,0,2) eq "\x23\xEF") || (substr($data,0,2) eq "\x21\xEF")){
				if (substr($data,0,2) eq "\x23\xEF"){
					print "\n-------- COMMAND -----------\n";
				}else{
					print "\n-------- RESPONSE ----------\n";
				}
				#Ch3 packet -> encrypt:
				$dlen = int(ord(substr($data,2,1))/2);
				print "LEN=$dlen\n";
				$ddat = substr($data,3,$dlen);
				print "Got cmd: <$ddat>\n";

				if ($ddat eq "AT*EACS=17,1\r"){
					#accept accessory status
					send_ch3_msg("\r\nOK\r\n");
				}elsif($ddat eq "AT+CSCC=1,199\r"){
					#accessory authentication
					send_ch3_msg("\r\n+CSCC: E3\r\n");
					send_ch3_msg("\r\nOK\r\n");

				}elsif($ddat eq "AT+CSCC=2,199,B9\r"){
					#phase2 of accessory auth done!
					send_ch3_msg("\r\nOK\r\n");

					#request channel1
					send_cmd("\xF9\x81\x3F\x01\xAB\xF9");
					
					                                        
				}elsif($ddat eq "AT*ECUR=41\r"){
					#device tells phone it needs 4.1mA
					#->send an ok
					send_ch3_msg("\r\nOK\r\n");


					#############################
					# init cam ?!
					send_ch1_data(
						 "\x82\x01\x3B\x01\x00".
						 "\x03\x49\x01\x35".
						 "<camera-settings version=\"1.0\" ".
						 "white-balance=\"OFF\" ".
						 "color-compensation=\"13\" ".
						 "fun-layer=\"0\">".
						 "<monitoring-format ".
						 "encoding=\"EBMP\" ".
						 "pixel-size=\"80*60\" ".
						 "color-depth=\"8\"/>\r\n".
						 "<thumbnail-format ".
						 "encoding=\"EBMP\" ".
						 "pixel-size=\"101*80\" ".
						 "color-depth=\"8\"/>\r\n".
						 "<native-format ".
						 "encoding=\"\" ".
						 "pixel-size=\"640x480\"/>\r\n".
						 "</camera-settings>\r\n"
						 );
						 
					send_ch1_data(
						 "\x83\x00\x17\x42\x00\x14".
						 "x-bt/camera-info\x00"
						 );
					
				}elsif($ddat eq "AT*ECUR=1000\r"){
					send_ch3_msg("\r\nOK\r\n");
					#send_cmd("\xF9\x81\xEF\x07\x83\x00\x03\xA6\xF9");
					
																				
				}
				
				
				
				
			}elsif( (substr($data,0,1) eq "\x83") || (substr($data,0,1) eq "\x81")){
				##print "########################## GOT DATA:\n";
				##print make_readable($data)."\n###############################\n";
				##print DAT "\xF9".$data.$check."\xF9";
				print "|$dlen|\n";
				
				# only save jpeg stream
				if($jpeg_stream==1){
					
					if ($skip != 1){
					  print DAT substr($data,3);			  
					}else{
					  print DAT substr($data,9);
					  $skip=0;
					}
				}

				if($data eq "\x83\xEF\x07\xA0\x00\x03"){
				      
					#got camera ACK
					#startmonitoring mode:
					if ($picmode < 5){
					send_ch1_data(
							"\x83\x00\x69\x71\x00\x3F".
							"<monitoring-command ".
							"version=\"1.0\" ".
							"take-pic=\"YES\" ".
							"zoom=\"10\"/>".
							"B\x00\x21".
							"x-bt/imaging-monitoring-image".
							"\x00\x4c\x00\x06\x06\x01\x80"
						);
					}else{

					send_ch1_data(
							"\x83\x00\x82\x71\x00\x58".
							"<monitoring-command ".
							"version=\"1.0\" ".
							"take-pic=\"NO\" ".
							"send-pixel-size=\"640*480\" ".
							"zoom=\"10\"/>".
							"B\x00\x21".
							"x-bt/imaging-monitoring-image".
							"\x00".
							"\x4c\x00\x06\x06\x01\x80"
					              );
					$jpeg_stream=1;
					}

					$picmode++;
					
				}

				if ($picmode!=0 && length($data)<25){
					  #send Picture ACKS:
					  send_ch1_data("\x83\x00\x03");
					  $skip = 1;
				}
				
			}
			
			$state = 1;
			$data = "";
		}
		
	}
}
while(1==0){
print "\n\nDISCONNECT\n";
while($res=getc(COM)){
	print "<$res\n";
}
}
close(COM);
close(OUT);

exit;


################################################################################################################

sub send_ch1_data(){
 my $c = shift;
 for (my $i=0; $i<length($c); ){
  my $out = substr($c, $i, min(31,length($c)-$i));
  #print "[$out]\n";
  send_ch1_msg($out);
  #sleep(1);
  $i += min(31,length($c)-$i);
 }
}



sub send_ch3_msg(){
	$msg = shift;
	$len = chr(length($msg)*2+1);
	$cdat = "\x21\xEF".$len;
	$checksum = chr(make_fcs($cdat));
        send_cmd("\xF9".$cdat.$msg.$checksum."\xF9");
}

sub send_ch1_msg(){
 my $d = shift;
 my $h = "\x81\xEF";
 my $l = chr(length($d)*2+1);
 send_cmd("\xF9". $h . $l . $d . chr(make_fcs($h.$l)) . "\xF9");  
}

sub send_control_command(){
 my $com = shift; 
 my $m_h = "\x81\xEF";
 my $mon = "\x83\x00\x17B\x00\x14";
 my $m_l = chr(length($mon)*2+1);
 send_cmd("\xF9".$m_h . $m_l . $mon . chr(make_fcs($m_h.$m_l))."\xF9");
 
 $mon = $com;
 $m_l = chr(length($mon)*2+1);
 send_cmd("\xF9".$m_h . $m_l . $mon . chr(make_fcs($m_h.$m_l))."\xF9");
}

sub send_ok(){
	#print OUT "\r\r\nOK\r\n";
	send_cmd("\r\r\nOK\r\n");
        #print ">> OK\n";			
	print "\n\n";
}

sub send_baudrates(){
	send_cmd("\r\n+IPR: (),(1200,2400,4800,9600)\r\n\r\nOK\r\n");
	#send_cmd("+IPR: (),(1200,2400,4800,9600)\r\n");
}

sub send_cmd(){
        $v = shift;
	print OUT $v;
	print LOG $v;
	
	$v2 = $v;
	$v2 =~ s/[\n]/\\n/gomi;;
	$v2 =~ s/[\r]/\\r/gomi;;
	print ">>SEND>>$v2<  [".encode($v)."]\n";
}
			
			sub encode {
			  my($text) = $_[0];
			    $text =~ s/(.)/ # replace odd chars
			      uc sprintf('%02x ',ord($1))/egx; # with %hex value
			    $text =~ s/\n/0A /gomi;
			    $text =~ s/\r/0D /gomi;
			        return $text; # return URL encoded text
				}
				
sub make_fcs(){
$input = shift;
@REVERSED_CRC_TABLE = (
				0x00, 0x91, 0xE3, 0x72, 0x07, 0x96, 0xE4, 0x75, 
				0x0E, 0x9F, 0xED, 0x7C, 0x09, 0x98, 0xEA, 0x7B, 
				0x1C, 0x8D, 0xFF, 0x6E, 0x1B, 0x8A, 0xF8, 0x69, 
				0x12, 0x83, 0xF1, 0x60, 0x15, 0x84, 0xF6, 0x67, 
				0x38, 0xA9, 0xDB, 0x4A, 0x3F, 0xAE, 0xDC, 0x4D, 
				0x36, 0xA7, 0xD5, 0x44, 0x31, 0xA0, 0xD2, 0x43, 
				0x24, 0xB5, 0xC7, 0x56, 0x23, 0xB2, 0xC0, 0x51, 
				0x2A, 0xBB, 0xC9, 0x58, 0x2D, 0xBC, 0xCE, 0x5F, 
				0x70, 0xE1, 0x93, 0x02, 0x77, 0xE6, 0x94, 0x05, 
				0x7E, 0xEF, 0x9D, 0x0C, 0x79, 0xE8, 0x9A, 0x0B, 
				0x6C, 0xFD, 0x8F, 0x1E, 0x6B, 0xFA, 0x88, 0x19, 
				0x62, 0xF3, 0x81, 0x10, 0x65, 0xF4, 0x86, 0x17, 
				0x48, 0xD9, 0xAB, 0x3A, 0x4F, 0xDE, 0xAC, 0x3D, 
				0x46, 0xD7, 0xA5, 0x34, 0x41, 0xD0, 0xA2, 0x33, 
				0x54, 0xC5, 0xB7, 0x26, 0x53, 0xC2, 0xB0, 0x21, 
				0x5A, 0xCB, 0xB9, 0x28, 0x5D, 0xCC, 0xBE, 0x2F, 
				0xE0, 0x71, 0x03, 0x92, 0xE7, 0x76, 0x04, 0x95, 
				0xEE, 0x7F, 0x0D, 0x9C, 0xE9, 0x78, 0x0A, 0x9B, 
				0xFC, 0x6D, 0x1F, 0x8E, 0xFB, 0x6A, 0x18, 0x89, 
				0xF2, 0x63, 0x11, 0x80, 0xF5, 0x64, 0x16, 0x87, 
				0xD8, 0x49, 0x3B, 0xAA, 0xDF, 0x4E, 0x3C, 0xAD, 
				0xD6, 0x47, 0x35, 0xA4, 0xD1, 0x40, 0x32, 0xA3, 
				0xC4, 0x55, 0x27, 0xB6, 0xC3, 0x52, 0x20, 0xB1, 
				0xCA, 0x5B, 0x29, 0xB8, 0xCD, 0x5C, 0x2E, 0xBF, 
				0x90, 0x01, 0x73, 0xE2, 0x97, 0x06, 0x74, 0xE5, 
				0x9E, 0x0F, 0x7D, 0xEC, 0x99, 0x08, 0x7A, 0xEB, 
				0x8C, 0x1D, 0x6F, 0xFE, 0x8B, 0x1A, 0x68, 0xF9, 
				0x82, 0x13, 0x61, 0xF0, 0x85, 0x14, 0x66, 0xF7, 
				0xA8, 0x39, 0x4B, 0xDA, 0xAF, 0x3E, 0x4C, 0xDD, 
				0xA6, 0x37, 0x45, 0xD4, 0xA1, 0x30, 0x42, 0xD3, 
				0xB4, 0x25, 0x57, 0xC6, 0xB3, 0x22, 0x50, 0xC1, 
				0xBA, 0x2B, 0x59, 0xC8, 0xBD, 0x2C, 0x5E, 0xCF 
			);

$fcs = 0xFF;
for (my $i=0;$i<length($input); $i++) {
  #printf("i=%d fcs=%02x substr=%02x fcs^substr=%02x\n",$i,$fcs,ord(substr($input,$i,1)),$fcs^ord(substr($input,$i,1)));
  $fcs = @REVERSED_CRC_TABLE[($fcs^ord(substr($input,$i,1)))];
}
return (0xFF-$fcs);
}

sub make_readable(){
	  my($text) = $_[0];
	  $text =~ s/[\n]/\\n/gomi;;
	  $text =~ s/[\r]/\\r/gomi;;
	  return $text; # return URL encoded text
}

sub min(){
 my $a = shift;
 my $b = shift;
 return ($a<$b?$a:$b);
}
   
