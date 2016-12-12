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
    "latency"    => 2
);

my %Snapcast_clientmethods = (
    "name"   => "Client.SetName",
    "volume"   => "Client.SetVolume",
    "mute"   => "Client.SetMute",
	"stream"   => "Client.SetStream",
	"latency"   => "Client.SetLatency"
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
          "streamnext:all,playing "
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
		$client = Snapcast_getMac($hash,$client);
		return "client not found, use unique name, IP, or MAC as client identifier" unless defined($client);
		my $value = shift @param;
		Snapcast_SetClient($hash,$client,$opt,$value);
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
  my $line = DevIo_Expect( $hash,Snapcast_Encode($hash,$method,$param),1);
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
        See <a href="http://fhem.de/commandref.html#define">commandref#define</a> 
        for more info about the define command.
    </ul>
    <br>
    <a name="Snapcastset"></a>
    <b>Set</b><br>
    <ul>
        <code>set &lt;name&gt; &lt;function&gt; &lt;client&gt; &lt;value&gt;</code>
        <br><br>
        See <a href="http://fhem.de/commandref.html#set">commandref#set</a> 
        for more info about the set command.
        <br><br>
        Options:
        <ul>
              <li><i>update</i><br>
                  Perform a full update of the Snapcast Status including streams and servers. Only needed if something is not working</li>
              <li><i>volume</i><br>
                  Set the volume of a client. For this and all the following options, give client as second parameter, either as name, IP , or MAC and the desired value as third parameter. Volume Range is 0-100</li>
              <li><i>mute</i><br>
                  Mute or unmute by giving true or false as value</li>
              <li><i>latency</i><br>
                  Change the Latency Setting of the Client</li>
              <li><i>stream</i><br>
                  Change the stream that the client is listening to. Snapcast uses one or more streams which can be unterstood as virtual audio channels. Each client/room can subscribe to one of them. 
                  By using next as value, you can cycle through the avaialble streams</li>
        </ul>
    </ul>
    <br>
</ul>

=end html

=cut