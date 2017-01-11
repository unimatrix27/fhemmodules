################################################################
#
#  $Id: 96_Snapcast.pm
#
#  Maintainer: Sebatian Stuecker / FHEM Forum: unimatrix / Github: unimatrix27
#  
#  FHEM Forum : https://forum.fhem.de/index.php/topic,62389.0.html
#
#  Github: https://github.com/unimatrix27/fhemmodules/blob/master/96_Snapcast.pm
#
#  Feedback bitte nur ins FHEM Forum, Bugs oder Pull Request bitte direkt auf Github. 
#
#  This code is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
################################################################


package main;
use strict;
use warnings;
use Scalar::Util qw(looks_like_number);

my $Snapcast_LogLevelDebug = 1;
my $Snapcast_LogLevelNormal = 1;
my $Snapcast_LogLevelCritical =1;


my %Snapcast_gets = (
	"tbd"	=> "x"
);

my %Snapcast_sets = (
    "update"   => 0,
    "volume"   => 2,
    "stream"   => 2,
    "name"	   => 2,
    "mute"    => 2,
    "latency"    => 2,
    "volumeConstraint" => 3
);

my %Snapcast_clientmethods = (
    "name"   => "Client.SetName",
    "volume"   => "Client.SetVolume",
    "mute"   => "Client.SetMute",
	"stream"   => "Client.SetStream",
	"latency"   => "Client.SetLatency",
	"volumeConstraint" => "internal"
);


sub Snapcast_Initialize($) {
    my ($hash) = @_;
	require "$attr{global}{modpath}/FHEM/DevIo.pm";
    $hash->{DefFn}      = 'Snapcast_Define';
    $hash->{UndefFn}    = 'Snapcast_Undef';
    $hash->{SetFn}      = 'Snapcast_Set';
    $hash->{GetFn}      = 'Snapcast_Get';
	$hash->{WriteFn}    = 'Snapcast_Write';
	$hash->{ReadyFn}    = 'Snapcast_Ready';
    $hash->{AttrFn}     = 'Snapcast_Attr';
    $hash->{ReadFn}     = 'Snapcast_Read';
    $hash->{TIMEOUT}	= 0.1;
    $hash->{AttrList} =
          "streamnext:all,playing constraintDummy volumeStep"
        . $readingFnAttributes;
}

sub Snapcast_Define($$) {
    my ($hash, $def) = @_;
    my @a = split('[ \t]+', $def);
    return "ERROR: perl module JSON is not installed" if (Snapcast_isPmInstalled($hash,"JSON"));
    $hash->{name}  = $a[0];
    $hash->{ip} = (defined($a[2])) ? $a[2] : "localhost"; 
    $hash->{port} = (defined($a[3])) ? $a[3] : "1705"; 
    readingsSingleUpdate($hash,"state","defined",1);
    RemoveInternalTimer($hash);
    DevIo_CloseDev($hash);
    $hash->{DeviceName} = $hash->{ip}.":".$hash->{port};
    DevIo_OpenDev(
            $hash, 0,
            "Snapcast_OnConnect",
        );
    return undef;
}

sub Snapcast_Attr($$){
	my ($cmd, $name, $attr, $value) = @_;
    my $hash = $defs{$name};
	if($attr eq "streamnext"){	
			return "streamnext needs to be either all or playing" unless $value=~/(all)|(playing)/;
	}
	return undef;
}

sub Snapcast_Undef($$) {
    my ($hash, $arg) = @_; 
    RemoveInternalTimer($hash);
    DevIo_CloseDev($hash);
    return undef;
}


sub Snapcast_Get($@) {
	my ($hash, @param) = @_;
	return '"get Snapcast" needs at least one argument' if (int(@param) < 2);
	
	my $name = shift @param;
	my $opt = shift @param;
	if(!$Snapcast_gets{$opt}) {
		my @cList = keys %Snapcast_gets;
		return "Unknown argument $opt, choose one of " . join(" ", @cList);
	}
	return "to be defined";
}

sub Snapcast_Set($@) {
	my ($hash, @param) = @_;
	
	return '"set Snapcast" needs at least one argument' if (int(@param) < 2);
	
	my $name = shift @param;
	my $opt = shift @param;
	my $value = join(" ", @param);
	
	if(!defined($Snapcast_sets{$opt})) {
		my @cList = keys %Snapcast_sets;
		return "Unknown argument $opt, choose one of " . join(" ", @cList);
	}
	if(@param < $Snapcast_sets{$opt}){
		return "$opt requires at least ".$Snapcast_sets{$opt}." arguments";
	}
	if($opt eq "update"){
		Snapcast_GetStatus($hash);
		return undef;
	}
	if(defined($Snapcast_clientmethods{$opt})){
		my $client = shift @param;
		$value = join(" ", @param);
		$client = Snapcast_getMac($hash,$client) unless $client eq "all";
		return "client not found, use unique name, IP, or MAC as client identifier" unless defined($client);
		if($client eq "all"){
			for(my $i=1;$i<=ReadingsVal($name,"clients",0);$i++){
				my $res = Snapcast_SetClient($hash,ReadingsVal($name,"clients_".$i."_mac",""),$opt,$value);
				readingsSingleUpdate($hash,"lastError",$res,1) if defined ($res);
				Log3 $name,3,ReadingsVal($name,"clients_".$i."_mac","");
			}
			return undef;
		}
		my $res = Snapcast_SetClient($hash,$client,$opt,$value);
		readingsSingleUpdate($hash,"lastError",$res,1) if defined ($res);
		return undef;
	}


	return "$opt not yet implemented $value";
}

sub Snapcast_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $buf;
  
  $buf = DevIo_SimpleRead($hash);
    return "" if ( !defined($buf) );
  $buf = $hash->{PARTIAL} . $buf;
  
  my $lastchr = substr( $buf, -1, 1 );
  if ( $lastchr ne "\n" ) {
      $hash->{PARTIAL} = $buf;
      Log3( $hash, 5, "snap: partial command received" );
      return;
  }
  else {
      $hash->{PARTIAL} = "";
  }

  my @lines = split( "\n", $buf );
  foreach my $line (@lines) {
    # Hier die Results parsen
    Log3 $name, 3, $line;
    my $update=decode_json($line);
    if($update->{method}=~/Client\.OnDelete/){
    	my $s=$update->{params}->{data};
    	fhem "deletereading $name clients.*";
    	Snapcast_GetStatus($hash);
    	return undef;
    }
    if($update->{method}=~/Client\./){
    	my $c=$update->{params}->{data};
    	Snapcast_UpdateClient($hash,$c,0);
    	return undef;
    }
    if($update->{method}=~/Stream\./){
    	my $s=$update->{params}->{data};
    	Snapcast_UpdateStream($hash,$s,0);
    	return undef;
    }

  }
}


sub Snapcast_Ready($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  if (AttrVal($hash->{NAME}, 'disable', 0)) {
    return;
  }
  if ( ReadingsVal( $name, "state", "disconnected" ) eq "disconnected" ) {
  		fhem "deletereading ".$name." streams.*";
  		fhem "deletereading ".$name." clients.*";
        DevIo_OpenDev($hash, 1,"Snapcast_OnConnect");
        return;
    }

  return undef;
}

sub Snapcast_OnConnect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  $hash->{LAST_CONNECT} = FmtDateTime( gettimeofday() );
  $hash->{CONNECTS}++;
  $hash->{helper}{PARTIAL} = "";
  Snapcast_GetStatus($hash);
  return undef;
 }

sub Snapcast_UpdateClient($$$){
	my ($hash,$c,$cnumber) = @_;
	if($cnumber==0){
		$cnumber++;
		while(defined($hash->{STATUS}->{clients}->{"$cnumber"}) && $c->{host}->{mac} ne $hash->{STATUS}->{clients}->{"$cnumber"}->{host}->{mac}){$cnumber++}
		if (not defined ($hash->{STATUS}->{clients}->{"$cnumber"})) { 
			Snapcast_GetStatus($hash);
			return undef;
		}
	}
	$hash->{STATUS}->{clients}->{"$cnumber"}=$c;
 	readingsBeginUpdate($hash);
 	readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_online",$c->{connected} ? 'true' : 'false' );
 	readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_name",$c->{config}->{name} ? $c->{config}->{name} : $c->{host}->{name} );
  	readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_latency",$c->{config}->{latency} );
  	readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_stream",$c->{config}->{stream} );
  	readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_volume",$c->{config}->{volume}->{percent} );
  	readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_muted",$c->{config}->{volume}->{muted} ? 'true' : 'false' );
  	readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_ip",$c->{host}->{ip} );
  	readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_mac",$c->{host}->{mac});
  	readingsEndUpdate($hash,1);
}



sub Snapcast_DeleteClient($$$){
	my ($hash,$mac) = @_;
	my $paramset;
	my $cnumber = Snapcast_getClientNumber($hash,$mac);
	return undef unless defined($cnumber);
	my $method="Server.DeleteClient";
	$paramset->{client}=$mac;
	my $result = Snapcast_Do($hash,$method,$paramset);
	return undef unless defined ($result);
	readingsSingleUpdate($hash,"state","Client Deleted: $cnumber",1);
	Snapcast_GetStatus($hash);
}

sub Snapcast_UpdateStream($$$){
	my ($hash,$s,$snumber) = @_;
	if($snumber==0){
		$snumber++;
		while(defined($hash->{STATUS}->{streams}->{"$snumber"}) && $s->{id} ne $hash->{STATUS}->{streams}->{"$snumber"}->{id}){$snumber++}
		if (not defined ($hash->{STATUS}->{streams}->{"$snumber"})){ return undef;}
	}
	$hash->{STATUS}->{streams}->{"$snumber"}=$s;
 	readingsBeginUpdate($hash);	
 	readingsBulkUpdateIfChanged($hash,"streams_".$snumber."_id",$s->{id} );
	readingsBulkUpdateIfChanged($hash,"streams_".$snumber."_status",$s->{status} );
  	readingsEndUpdate($hash,1);
}


sub Snapcast_GetStatus($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  my $status=Snapcast_Do($hash,"Server.GetStatus",'');
  return undef unless defined ($status);
  my $streams=$status->{result}->{streams};
  my $clients=$status->{result}->{clients};
  my $server=$status->{result}->{server};

  
  $hash->{STATUS}->{server}=$server;
  if(defined ($clients)){
  	my @clients=@{$clients};
  	my $cnumber=1;
  	foreach my $c(@clients){
	  	Snapcast_UpdateClient($hash,$c,$cnumber);
	  	$cnumber++;
  	}
  	readingsBeginUpdate($hash);	
    readingsBulkUpdateIfChanged($hash,"clients",$cnumber-1 );
    readingsEndUpdate($hash,1);
  }
  if(defined ($streams)){
  	my @streams=@{$streams} unless not defined ($streams);
  	my $snumber=1;
  	foreach my $s(@streams){
	  	Snapcast_UpdateStream($hash,$s,$snumber);
	  	$snumber++;
  	}
  	readingsBeginUpdate($hash);	
  	readingsBulkUpdateIfChanged($hash,"streams",$snumber-1 );
  	readingsEndUpdate($hash,1);
  }
    InternalTimer(gettimeofday() + 600, "Snapcast_GetStatus", $hash, 1); # every 10 minutes the complete status is updated to be on the safe side
}

sub Snapcast_SetClient($$$$){
	my ($hash,$mac,$param,$value) = @_;
	my $name = $hash->{NAME};
	my $method;
	my $paramset;
	my $cnumber = Snapcast_getClientNumber($hash,$mac);
	return undef unless defined($cnumber);
	$paramset->{client}=$mac;
	return undef unless defined($Snapcast_clientmethods{$param});
	$method=$Snapcast_clientmethods{$param};
	if($param eq "volumeConstraint"){
		my @values=split(/ /,$value);
		my $match;
		return "not enough parameters for volumeConstraint" unless @values>=2;
		if(@values%2){ # there is a match argument given because number is uneven
			$match=pop(@values);
		}else{$match="_global_"}
		for(my $i=0;$i<@values;$i+=2){
			return "wrong timeformat 00:00 - 24:00 for time/volume pair" unless @values[$i]=~/^(([0-1]?[0-9]|2[0-3]):[0-5][0-9])|24:00$/;
			return "wrong volumeformat 0 - 100 for time/volume pair" unless @values[$i+1]=~/^(0?[0-9]?[0-9]|100)$/;
		}
		readingsSingleUpdate($hash,"volumeConstraint_".$mac."_".$match,$value,1);
		return undef;
	}
	if($param eq "stream"){
		$param="id";
		if($value eq "next"){ # just switch to the next stream, if last stream, jump to first one. This way streams can be cycled with a button press
			my $totalstreams=ReadingsVal($name,"streams","");
			my $currentstream = ReadingsVal($name,"clients_".$cnumber."_stream","");
			$currentstream = Snapcast_getStreamNumber($hash,$currentstream);
			
			my $newstream = $currentstream+1;
			$newstream=1 unless $newstream <= $totalstreams;
			while(AttrVal($name, 'streamnext', 'all') eq 'playing' && ReadingsVal($name,"streams_".$newstream."_status","") ne "playing" && $newstream!=$currentstream ) {
				$newstream++;
				$newstream=1 unless $newstream <= $totalstreams;
			}
			$value=ReadingsVal($name,"streams_".$newstream."_id","");
		}
	}
  if($param eq "volume" && $value=~/^([\+\-])(\d{1,2})$/){
    my $direction = $1;
    my $amount = $2;
    my $currentVol = Snapcast_GetVolume($hash,$mac);
    return undef unless defined($currentVol);
    if($direction eq "+"){$value = $currentVol + $amount;}else{$value = $currentVol - $amount;}
    $value = 100 if ($value >= 100);
    $value = 0 if ($value <0);
   
  }
	if(looks_like_number($value)){
		$paramset->{"$param"} = $value+0;
	}else{
		$paramset->{"$param"} = $value
	}

	Log3 $name,3,"$name $method $mac $param $value";
	my $result = Snapcast_Do($hash,$method,$paramset);
	return undef unless defined ($result);
	$param=~s/id/stream/;
	readingsBeginUpdate($hash);	
	readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_".$param,$result->{result} );
	readingsEndUpdate($hash,1);
}



sub Snapcast_Do($$$){
  my ($hash,$method,$param) = @_;
  $param = '' unless defined($param);
  my $line = DevIo_Expect( $hash,Snapcast_Encode($hash,$method,$param),$hash->{TIMEOUT});
  return undef unless defined($line);
  if($line=~/error/){
  	readingsSingleUpdate($hash,"lastError",$line,1);
  	return undef;
  }
  return decode_json($line);
}

sub Snapcast_Encode($$$){
  my ($hash,$method,$param) = @_;
  my $name = $hash->{NAME};
  if(defined($hash->{helper}{REQID})){$hash->{helper}{REQID}++;}else{$hash->{helper}{REQID}=1;}
  my $request;
  my $json;
  $request->{jsonrpc}="2.0";
  $request->{method}=$method;
  $request->{id}=$hash->{helper}{REQID};
  $request->{params} = $param unless $param eq '';
  Log3 $name,3,encode_json($request)."\r\n";
  $json=encode_json($request)."\r\n";
  $json =~s/\"true\"/true/;			# Snapcast needs bool values without "" but encode_json does not do this
  $json =~s/\"false\"/false/;
  return $json;
}

sub Snapcast_getClientNumber($$){
	my ($hash,$mac) = @_;
	my $name = $hash->{NAME};
	for(my $i=1;$i<=ReadingsVal($name,"clients",1);$i++){
		if ($mac eq ReadingsVal($name,"clients_".$i."_mac","")){
			return $i;
		}
	}
	return undef;
}

sub Snapcast_GetVolume($$){
  my ($hash,$mac) = @_;
  my $name = $hash->{NAME};
  for(my $i=1;$i<=ReadingsVal($name,"clients",1);$i++){
    if ($mac eq ReadingsVal($name,"clients_".$i."_mac","")){
      return ReadingsVal($name,"clients_".$i."_volume","");
    }
  }
  return undef;
}


sub Snapcast_getStreamNumber($$){
	my ($hash,$id) = @_;
	my $name = $hash->{NAME};
	for(my $i=1;$i<=ReadingsVal($name,"streams",1);$i++){
		if ($id eq ReadingsVal($name,"streams_".$i."_id","")){
			return $i;
		}
	}
	return undef;
}


sub Snapcast_getMac($$){
	my ($hash,$client) = @_;
	my $name = $hash->{NAME};
	if($client=~/^([0-9a-f]{2}([:-]|$)){6}$/i){ # client is already a MAC
		return $client;
	}
	if($client =~ qr/^(?!(\.))(\.?(\d{1,3})(?(?{$^N > 255})(*FAIL))){4}$/){ # client is given as IP address
		for(my $i=1;$i<=ReadingsVal($name,"clients",1);$i++){
			if ($client eq ReadingsVal($name,"clients_".$i."_ip","")){
				return ReadingsVal($name,"clients_".$i."_mac","");
			}
		}
	}
	for(my $i=1;$i<=ReadingsVal($name,"clients",1);$i++){
		if ($client eq ReadingsVal($name,"clients_".$i."_name","")){
			return ReadingsVal($name,"clients_".$i."_mac","");
		}
	}
}

sub Snapcast_isPmInstalled($$)
{
  my ($hash,$pm) = @_;
  my ($name,$type) = ($hash->{NAME},$hash->{TYPE});
  if (not eval "use $pm;1")
  {
    Log3 $name, 1, "$type $name: perl modul missing: $pm. Install it, please.";
    return "failed: $pm";
  }
  
  return undef;
}
1;

=pod
=item summary    control and monitor Snapcast Server
=begin html

<a name="Snapcast"></a>
<h3>Snapcast</h3>
<ul>
    <i>Snapcast</i> is a module to control a Snapcast Server. Snapcast is a little project to achieve multiroom audio and is a leightweight alternative to such solutions using Pulseaudio.
    Find all information about Snapcast, how to install and configure on the <a href="https://github.com/badaix/snapcast">Snapcast GIT</a>
    <br><br>
    <a name="Snapcastdefine"></a>
    <b>Define</b>
    <ul>
        <code>define <name> Snapcast [&lt;ip&gt; &lt;port&gt;]</code>
        <br><br>
        Example: <code>define MySnap Snapcast 127.0.0.1 1705</code>
        <br><br>
        IP defaults to localhost, and Port to 1705, in case you run Snapcast in the default configuration on the same server as FHEM, you dont need to give those parameters.
    </ul>
    <br>
    <a name="Snapcastset"></a>
    <b>Set</b><br>
    <ul>
        <code>set &lt;name&gt; &lt;function&gt; &lt;client&gt; &lt;value&gt;</code>
        <br><br>

        Options:
        <ul>
              <li><i>update</i><br>
                  Perform a full update of the Snapcast Status including streams and servers. Only needed if something is not working</li>
              <li><i>volume</i><br>
                  Set the volume of a client. For this and all the following 4 options, give client as second parameter, either as name, IP , or MAC and the desired value as third parameter. 
                  Client can be given as "all", in that case all clients are changed at once. Volume Range is 0-100 or given as step using +/- e.g  -10 decreases the volume with an amount of 10</li>
              <li><i>mute</i><br>
                  Mute or unmute by giving "true" or "false" as value. Use "toggle" to toggle between muted and unmuted.</li>
              <li><i>latency</i><br>
                  Change the Latency Setting of the client</li>
              <li><i>name</i><br>
                  Change the Name of the client</li>
              <li><i>stream</i><br>
                  Change the stream that the client is listening to. Snapcast uses one or more streams which can be unterstood as virtual audio channels. Each client/room can subscribe to one of them. 
                  By using next as value, you can cycle through the avaialble streams</li>
        </ul>
</ul>
 <br><br>
  <a name="Snapcastattr"></a>
  <b>Attributes</b>
  <ul>
    <li>streamnext<br>
    Can be set to <i>all</i> or <i>playing</i>. If set to <i>all</i>, the <i>next</i> function cycles through all streams, if set to <i>playing</i>, the next function cycles only through streams in the playing state.
    </li>
        <li>constraintDummy<br>
    Links the Snapcast module to a dummy. The value of the dummy is then used as a selector for different sets of volumeConstraints. See the description of the volumeConstraint command.
    </li>

  </ul>
</ul>

=end html

=currentstream