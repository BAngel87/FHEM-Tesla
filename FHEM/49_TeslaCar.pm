=head1
        49_TeslaCar.pm

# $Id: $

        Version 1.2

=head1 SYNOPSIS
        Tesla Motors Modul for FHEM
        contributed by Stefan Willmeroth 07/2017

        Get started by defining a TeslaConnection and search your cars:
        define teslaconn TeslaConnection
        set teslaconn scanCars

        Use my referral code to get unlimited supercharging for
        your new Tesla: http://ts.la/stefan1473
			https://ts.la/timo72139 ;-)
			
			Anpassungen bzgl. WakeUp + Sleep

=head1 DESCRIPTION
        49_TeslaCar handles individual cars defines by
        49_TeslaConnection

=head1 AUTHOR - Stefan Willmeroth
        swi@willmeroth.com (forum.fhem.de)
=cut

package main;

use strict;
use warnings;
use JSON;
use Switch;
require 'HttpUtils.pm';


##############################################
#my $TeslaCar_headers="speed,odometer,soc,est_lat,est_lng,power,shift_state";

my $TeslaCar_headers="speed,odometer,soc,elevation,est_heading,est_lat,est_lng,".
                     "power,shift_state,range,est_range,heading";

my @TeslaCar_ConvertToKM = (
  "speed","odometer","battery_range","est_battery_range","ideal_battery_range"
);

my @TeslaCar_Data_Nodes = (
  "drive_state","vehicle_state","vehicle_config","charge_state","drive_state",
  "climate_state","gui_settings"
);

##############################################
sub TeslaCar_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "TeslaCar_Set";
  $hash->{DefFn}     = "TeslaCar_Define";
  $hash->{GetFn}     = "TeslaCar_Get";
  $hash->{AttrList}  = "updateTimer pollingTimer streamingTimer dataRequest stateFormat";
}

###################################
sub TeslaCar_Set($@)
{
  my ($hash, @a) = @_;
  my $rc = undef;
  my $reDOUBLE = '^(\\d+\\.?\\d{0,2})$';
  my $JSON = JSON->new->utf8(0)->allow_nonref;

  my $carId = $hash->{carId};
  my $availableCmds;

  if (Value($hash->{teslaconn}) ne "Connected") {
    $availableCmds = "not logged in";
  } else {
    $availableCmds ="init requestSettings wakeUpCar charge_limit_soc startCharging stopCharging flashLights honkHorn temperature startHvacSystem stopHvacSystem unlock lock";
  }

  return "no set value specified" if(int(@a) < 2);
  return $availableCmds if($a[1] eq "?");

  shift @a;
  my $command = shift @a;

  Log3 $hash->{NAME}, 2, "set command: $command";

  if($command eq "wakeUpCar") {
    my $URL = "/api/1/vehicles/$carId/wake_up";
    $rc = TeslaConnection_postrequest($hash,$URL);
  }
  if($command eq "flashLights") {
    my $URL = "/api/1/vehicles/$carId/command/flash_lights";
    $rc = TeslaConnection_postrequest($hash,$URL);
  }
  if($command eq "honkHorn") {
    my $URL = "/api/1/vehicles/$carId/command/honk_horn";
    $rc = TeslaConnection_postrequest($hash,$URL);
  }
  if($command eq "startCharging") {
    my $URL = "/api/1/vehicles/$carId/command/charge_start";
    $rc = TeslaConnection_postrequest($hash,$URL);
  }
  if($command eq "stopCharging") {
    my $URL = "/api/1/vehicles/$carId/command/charge_stop";
    $rc = TeslaConnection_postrequest($hash,$URL);
  }
  if($command eq "startHvacSystem") {
    my $URL = "/api/1/vehicles/$carId/command/auto_conditioning_start";
    $rc = TeslaConnection_postrequest($hash,$URL);
  }
  if($command eq "unlock") {
    my $URL = "/api/1/vehicles/$carId/command/door_unlock";
    $rc = TeslaConnection_postrequest($hash,$URL);
  }
  if($command eq "lock") {
    my $URL = "/api/1/vehicles/$carId/command/door_lock";
    $rc = TeslaConnection_postrequest($hash,$URL);
  }
  if($command eq "stopHvacSystem") {
    my $URL = "/api/1/vehicles/$carId/command/auto_conditioning_stop";
    $rc = TeslaConnection_postrequest($hash,$URL);
  }
  if($command eq "charge_limit_soc") {
    my $min = ReadingsVal($hash->{NAME},"charge_limit_soc_min",50);
    my $max = ReadingsVal($hash->{NAME},"charge_limit_soc_max",100);
    return "Need the new charge limit percentage as numeric argument ($min-$max)"
          if(int(@a) < 1 || $a[0]<$min || $a[0]>$max );
    $rc = TeslaConnection_setChargeLimit($hash,$a[0]);
  }
  if($command eq "temperature") {
    my $min = ReadingsVal($hash->{NAME},"min_avail_temp",15);
    my $max = ReadingsVal($hash->{NAME},"max_avail_temp",28);
    return "Need the new temperature as numeric argument"
          if(int(@a) < 1 || $a[0]<$min || $a[0]>$max);
    $rc = TeslaConnection_setTemperature($hash,$a[0]);
  }
  ## Connect event channel, update status
  if($command eq "init") {
    return TeslaCar_Init($hash);
  }
  ## Request Car settings
  if($command eq "requestSettings") {
    TeslaCar_UpdateStatus($hash, 1);
  }
  return $rc;
}

#####################################
sub TeslaCar_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $u = "wrong syntax: define <dev-name> TeslaCar <conn-name> <vin> to add a new car";

  return $u if(int(@a) < 4);

  $hash->{teslaconn} = $a[2];
  $hash->{vin} = $a[3];

  #### Delay init if not yet connected
  return undef if(Value($hash->{teslaconn}) ne "Connected");

  my $err = TeslaCar_Init($hash);

  #### Some first time setup stuff
  $attr{$hash->{NAME}}{alias} = $hash->{aliasname} if (!defined $attr{$hash->{NAME}}{alias} && defined $hash->{aliasname});
  $attr{$hash->{NAME}}{dataRequest} = "data" if (!defined $attr{$hash->{NAME}}{dataRequest});
  $attr{$hash->{NAME}}{pollingTimer} = "60" if (!defined $attr{$hash->{NAME}}{pollingTimer});
  $attr{$hash->{NAME}}{updateTimer} = "600" if (!defined $attr{$hash->{NAME}}{updateTimer});
  $attr{$hash->{NAME}}{streamingTimer} = "1" if (!defined $attr{$hash->{NAME}}{streamingTimer});

  Log3 $hash->{NAME}, 2, "$hash->{NAME} defined as TeslaCar $hash->{vin}" if !defined($err);
  return $err;
}

#####################################
sub TeslaCar_Init($)
{
  my ($hash) = @_;

  my $err = TeslaCar_UpdateStatus($hash, 1);

  if (!defined($err)) {
      RemoveInternalTimer($hash);
      TeslaCar_CloseEventChannel($hash);
      TeslaCar_Timer($hash);
  }
  return $err;
}

#####################################
sub TeslaConnection_setChargeLimit($$)
{
  my ($hash, $chargeLimit) = @_;
  my $carId = $hash->{carId};

  my $URL = "/api/1/vehicles/$carId/command/set_charge_limit";
  my $rc = TeslaConnection_postdatarequest($hash,$URL,
    "{\"percent\": $chargeLimit}");
  return $rc;
}

#####################################
sub TeslaConnection_setTemperature($$)
{
  my ($hash, $temperature) = @_;
  my $carId = $hash->{carId};

  my $URL = "/api/1/vehicles/$carId/command/set_temps";
  my $rc = TeslaConnection_postdatarequest($hash,$URL,
    "{\"driver_temp\": $temperature, \"passenger_temp\": $temperature}");
  return $rc;
}

#####################################
sub TeslaCar_Undef($$)
{
   my ( $hash, $arg ) = @_;

   RemoveInternalTimer($hash);
   TeslaCar_CloseEventChannel($hash);
   Log3 $hash->{NAME}, 3, "--- removed ---";
   return undef;
}

#####################################
sub TeslaCar_Get($@)
{
  my ($hash, @args) = @_;

  return "TeslaCar_Get not supported";
}

#####################################
sub TeslaCar_Timer
{
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my $pollingTimer   = AttrVal($name, "pollingTimer", 60);
  my $updateTimer    = AttrVal($name, "updateTimer", 600);
  my $streamingTimer = AttrVal($name, "streamingTimer", 1);
  my $dataRequest    = AttrVal($name, "dataRequest", "");

  my $odometerChangeAge = gettimeofday() - time_str2num(ReadingsTimestamp($name,"odometer",gettimeofday()));
  my $stateChangeAge    = gettimeofday() - time_str2num(ReadingsTimestamp($name,"state",gettimeofday()));
  my $ParkingAge	    = gettimeofday() - time_str2num(ReadingsTimestamp($name,"shift_state",gettimeofday()));

  Log3 $hash->{NAME}, 4, "Last odometer change: $odometerChangeAge, last state change $stateChangeAge";

  $hash->{skipFull}+=$pollingTimer;

  my $requestFullStatus = (
    ReadingsVal($name,"state",undef) eq "online" &&          # request full status at this poll when online and
      (
      $hash->{skipFull} >= $updateTimer && $stateChangeAge > (24*$pollingTimer)  ||          # at least all $updateTimer seconds wenn mehr als 4 Minuten online
       (
        #$odometerChangeAge < (18*$pollingTimer) ||                 	# or if speed has changed between the last three polls
        #$stateChangeAge > (24*$pollingTimer) ||                    		# or if state has changed between the last three polls
		$ParkingAge < (30*$pollingTimer) ||                    			# or if car has been parked the last 5 minutes
        ReadingsVal($name,"charging_state","none") eq "Charging" ||  	# or if car is charging
		ReadingsVal($name,"shift_state","none") ne "P" ||  				# or if car is not in P
		ReadingsVal($name,"locked","none") == 0 ||  					# or if car is unlocked
		ReadingsVal($name,"sentry_mode","none") == 1 				 	# or if car is in sentry mode
		
        )
      )
    );

  if (defined $hash->{conn}) {
    if ($requestFullStatus && index($dataRequest, "stream") >-1) {
      TeslaCar_ReadEventChannel($hash) ;
    } else {
      TeslaCar_CloseEventChannel($hash);
    }
  }

  # if event channel is not connected
  if (!defined $hash->{conn}) {
    # read regular api information
    my $err = TeslaCar_UpdateStatus($hash, $requestFullStatus);
    $hash->{skipStatus}=0;
    $hash->{skipFull}=0 if ($requestFullStatus);

    if ($requestFullStatus && index($dataRequest, "stream") > -1) {
      # a new connection attempt is needed
      TeslaCar_ConnectEventChannel($hash);
      InternalTimer( gettimeofday() + $streamingTimer, "TeslaCar_Timer", $hash, 0);
    } else {
      # car is sleeping
      InternalTimer( gettimeofday() + $pollingTimer, "TeslaCar_Timer", $hash, 0);
    }
  } else {
    # quick polling of event stream
    InternalTimer( gettimeofday() + $streamingTimer, "TeslaCar_Timer", $hash, 0);

    $hash->{skipStatus}+=$streamingTimer;
    # read regular api information in scheduled intervals
    if ($hash->{skipStatus}>=$pollingTimer) {
       TeslaCar_UpdateStatus($hash, 1);
       $hash->{skipStatus}=0;
       $hash->{skipFull}=0;
    }
  }
}

#####################################
sub TeslaCar_UpdateStatus($$)
{
  my ($hash, $requestFullStatus) = @_;
  my $JSON = JSON->new->utf8(0)->allow_nonref;


  #### Read list of cars, find my carId
  my $URL = "/api/1/vehicles";

  my $carJson = TeslaConnection_request($hash,$URL);
  if (!defined $carJson || $carJson eq "") {
    return "Failed to connect to TeslaCar API, see log for details";
  }

  my $cars = eval {$JSON->decode ($carJson)};
  if($@){
    Log3 $hash->{NAME}, 3, "$hash->{NAME} - JSON error requesting vehicles: $@";
  } else {
    for (my $i = 0; 1; $i++) {
      my $car = $cars->{response}[$i];
      if (!defined $car) { last };
      if ($hash->{vin} eq $car->{vin}) {
#        $hash->{option_codes} = $car->{option_codes};
        $hash->{aliasname}  = $car->{display_name};
        $hash->{carId}      = $car->{id};
        $hash->{vehicle_id} = $car->{vehicle_id};
        $hash->{tokens}     = $car->{tokens};

        Log3 $hash->{NAME}, 4, $hash->{STATE};

        #### Update State
        if (ReadingsVal($hash->{NAME},"state",undef) ne $car->{state}) {
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash, "state", $car->{state});
          readingsEndUpdate($hash, 1);
          # always read all data and update all values after coming online
          if ($car->{state} eq "online") {
            #$requestFullStatus = 1;
            $hash->{updateAllValues} = 0;
          }
        } else {
          $hash->{updateAllValues} = 0;
        }

        my $dataRequest = AttrVal($hash->{NAME},"dataRequest","");

        if ($car->{state} eq "online" && $requestFullStatus) {
          my @names = ();
          push @names, "vehicle_data"                if (index($dataRequest, "data")>-1);
          push @names, "data_request/vehicle_state"  if (index($dataRequest, "vehicle")>-1);
          push @names, "data_request/charge_state"   if (index($dataRequest, "charge")>-1);
          push @names, "data_request/drive_state"    if (index($dataRequest, "drive")>-1);
          push @names, "data_request/climate_state"  if (index($dataRequest, "climate")>-1);
          push @names, "data_request/gui_settings"   if (index($dataRequest, "gui")>-1);
          push @names, "data_request/vehicle_config" if (index($dataRequest, "config")>-1);
          $hash->{topics} = [@names];
          TeslaCar_UpdateVehicleStatus($hash);
        }
        return undef;
      }
    }
    return "Specified car with VIN $hash->{vin} not found";
  }
}

#####################################
sub TeslaCar_UpdateVehicleStatus($)
{
  my ($hash) = @_;
  my $carId = $hash->{carId};
  my $name  = $hash->{NAME};
  my $topic = pop (@{$hash->{topics}});
  return undef if (!defined($topic));

  TeslaConnection_RefreshToken($hash);

  my $conn = (defined $hash->{teslaconn}) ? $hash->{teslaconn} : $hash->{NAME};
  my $api_uri = $defs{$conn}->{api_uri};
  my ($gkerror, $token) = getKeyValue($conn."_accessToken");

  #### Get status variables
  my $param = {
    url        => $api_uri . "/api/1/vehicles/$carId/$topic",
    hash       => $hash,
    header     => { "Accept" => "application/json", "Authorization" => "Bearer $token" },
    timeout    => 10,
    callback   => \&TeslaCar_UpdateVehicleCallback
  };

  Log3 $name, 5, "$name request: $param->{url}";

  HttpUtils_NonblockingGet($param);

  return undef;
}

#####################################
sub TeslaCar_UpdateVehicleCallback($)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my %readings = ();
  my $JSON = JSON->new->utf8(0)->allow_nonref;

  if($err ne "") {
    Log3 $name, 2, "error while requesting ".$param->{url}." - $err";
  }
  elsif($data ne "") {
    Log3 $name, 5, "$name returned: $data";

    my $parsed = eval {$JSON->decode ($data)};
    if($@){

      Log3 $hash->{NAME}, 3, "$hash->{NAME} - JSON error requesting data: $@";

    } else {

      foreach my $reading (keys %{$parsed->{response}}) {
        if (grep( /^$reading$/, @TeslaCar_Data_Nodes)) {
          foreach my $subreading (keys %{$parsed->{response}->{$reading}}) {
            $readings{$subreading} = $parsed->{response}->{$reading}->{$subreading};
          }
        }
        else {
          $readings{$reading} = $parsed->{response}->{$reading};
        }
      }

      if (defined $readings{"latitude"} && defined $readings{"longitude"}) {
        $readings{"position"}=$readings{"latitude"} .", ".$readings{"longitude"};
        delete $readings{"latitude"};
        delete $readings{"longitude"};
      }

      if (defined $readings{"timestamp"}) {
        delete $readings{"timestamp"};
      }

      if (defined $readings{"tokens"}) {
        delete $readings{"tokens"};
      }

      foreach my $key ( @TeslaCar_ConvertToKM ) {
        if (defined $readings{$key}) {
          $readings{$key} *= 1.60934;
        }
      }

      if (defined $readings{"speed"}) {
        $readings{"speed"} = 0 + $readings{"speed"};
      }

      if (defined $readings{"software_update"}) {
        foreach my $subreading (keys %{$readings{"software_update"}}) {
          $readings{$subreading} = $readings{"software_update"}->{$subreading};
        }
        delete $readings{"software_update"};
      }

      #### Update Readings
      readingsBeginUpdate($hash);

      for my $get (keys %readings) {
        my $current = ReadingsVal($hash->{NAME},$get,undef);
        my $setval = defined $readings{$get} ? $readings{$get} :
          (defined $current && looks_like_number($current) ? 0: "");

        readingsBulkUpdate($hash, $get, $readings{$get})
                  if ($hash->{updateAllValues} || $current ne $setval);
      }
      readingsEndUpdate($hash, 1);
    }
  }
  TeslaCar_UpdateVehicleStatus($hash);
  return undef;
}

#####################################
sub TeslaCar_ConnectEventChannel
{
  my ($hash) = @_;
  my $api_uri = $defs{$hash->{teslaconn}}->{api_uri};

  my $param = {
    url => "https://streaming.vn.teslamotors.com/stream/$hash->{vehicle_id}?values=$TeslaCar_headers",
    hash       => $hash,
    auth       => $defs{$hash->{teslaconn}}->{username} .":". $hash->{tokens}[0],
    timeout    => 10,
    noshutdown => 1,
    noConn2    => 1,
    callback   => \&TeslaCar_HttpConnected
  };

  Log3 $hash->{NAME}, 5, "$hash->{NAME} connecting to event channel with auth " . $param->{auth};

  HttpUtils_NonblockingGet($param);

}

#####################################
sub TeslaCar_HttpConnected
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  # this is a callback used by HttpUtils_NonblockingGet
  # it will be called after the http socket connection has been opened
  # and handles the http protocol part.

  # make sure we're really connected
  if (!defined $param->{conn}) {
    TeslaCar_CloseEventChannel($hash);
    return;
  }

  my ($gterror, $token) = getKeyValue($hash->{teslaconn}."_accessToken");
  my $method = $param->{method};
  $method = ($data ? "POST" : "GET") if( !$method );

  my $httpVersion = $param->{httpversion} ? $param->{httpversion} : "1.0";
  my $hdr = "$method $param->{path} HTTP/$httpVersion\r\n";
  $hdr .= "Host: $param->{host}\r\n";
  $hdr .= "User-Agent: fhem\r\n" if(!$param->{header} || $param->{header} !~ "User-Agent:");
  $hdr .= "Accept: text/event-stream\r\n";
  $hdr .= "Accept-Encoding: gzip,deflate\r\n" if($param->{compress});
  $hdr .= "Connection: keep-alive\r\n" if($param->{keepalive});
  $hdr .= "Connection: Close\r\n" if($httpVersion ne "1.0" && !$param->{keepalive});
  $hdr .= "Authorization: Basic ".encode_base64($param->{auth}, "")."\r\n" if(defined($param->{auth}));

  if(defined($data)) {
    $hdr .= "Content-Length: ".length($data)."\r\n";
    $hdr .= "Content-Type: application/x-www-form-urlencoded\r\n" if ($hdr !~ "Content-Type:");
  }
  $hdr .= "\r\n";

  Log3 $hash->{NAME}, 5, "$hash->{NAME} sending headers to event channel: $hdr";

  syswrite $param->{conn}, $hdr;
  $hash->{conn} = $param->{conn};
  $hash->{eventChannelTimeout} = time();

  Log3 $hash->{NAME}, 5, "$hash->{NAME} connected to event channel";

  # the server connection is left open to receive new events
}

#####################################
sub TeslaCar_CloseEventChannel($)
{
  my ( $hash ) = @_;

  if (defined $hash->{conn}) {
    $hash->{conn}->close();
    delete($hash->{conn});
    Log3 $hash->{NAME}, 5, "$hash->{NAME} disconnected from event channel";
  }
}

#####################################
sub TeslaCar_ReadEventChannel($)
{
  my ($hash) = @_;
  my $inputbuf;
  my $JSON = JSON->new->utf8(0)->allow_nonref;

  while (defined $hash->{conn}) {
    my ($rout, $rin) = ('', '');
    vec($rin, $hash->{conn}->fileno(), 1) = 1;

    # check for timeout
#    if (defined $hash->{eventChannelTimeout} &&
#        (time() - $hash->{eventChannelTimeout}) > 130) {
#      Log3 $hash->{NAME}, 2, "$hash->{NAME} event channel timeout, two keep alive messages missing";
#      TeslaCar_CloseEventChannel($hash);
#      return undef;
#    }

    # check channel data availability
#    Log3 $hash->{NAME}, 5, "$hash->{NAME} event channel searching for data";
    my $nfound = select($rout=$rin, undef, undef, 0);
    if($nfound < 0) {
      Log3 $hash->{NAME}, 2, "$hash->{NAME} event channel timeout/error: $!";
      TeslaCar_CloseEventChannel($hash);
      return undef;
    }

    # read data
    if($nfound > 0) {
      my $len = sysread($hash->{conn},$inputbuf,32768);

      # check if something was actually read
      if (defined($len) && $len > 0 && defined($inputbuf) && length($inputbuf) > 0) {

        # process data
#        Log3 $hash->{NAME}, 5, "$hash->{NAME} event channel received $inputbuf";
        my %readings = ();

        # reset timeout
        $hash->{eventChannelTimeout} = time();

        # split data into lines,
        for (split /^/, $inputbuf) {
          # check for http result line
          if (index($_,"HTTP/1.1") == 0) {
            if (substr($_,9,3) ne "200") {
               Log3 $hash->{NAME}, 2, "$hash->{NAME} event channel received an http error: $_";
               TeslaCar_CloseEventChannel($hash);
               return undef;
            } else {
               # successful connection, reset counter
               $hash->{retrycounter} = 0;
            }
          }
          # extract data elements
          if ($_ =~ tr/\,// == 12) {
            my $json = $_;
            Log3 $hash->{NAME}, 5, "$hash->{NAME} event channel data: $json";
            my @headers =  split /\,/, "timestamp,".$TeslaCar_headers;
            foreach my $element ( split  /\,/, $json ) {
#              Log3 $hash->{NAME}, 5, "$headers[0] = $element\r\n";
              $readings{$headers[0]} = $element;
              shift @headers;
            }
          }
        }
        # combine position to single reading
        $readings{"position"}=$readings{"est_lat"} .", ".$readings{"est_lng"};
        $readings{"battery_level"}=$readings{"soc"};
        delete $readings{"est_lat"};
        delete $readings{"est_lng"};
        delete $readings{"timestamp"};
        delete $readings{"soc"};

        foreach my $key ( @TeslaCar_ConvertToKM ) {
          if (defined $readings{$key}) {
            $readings{$key} *= 1.60934;
          }
        }

        # update readings from elements
        readingsBeginUpdate($hash);
        for my $get (keys %readings) {
          readingsBulkUpdate($hash, $get, $readings{$get})
                 if (ReadingsVal($hash->{NAME},$get,undef) ne $readings{$get});
        }
        readingsEndUpdate($hash, 1);
      } else {
        Log3 $hash->{NAME}, 5, "$hash->{NAME} event channel read failed, closing";
        TeslaCar_CloseEventChannel($hash);
        return undef;
      }
    } else {
      return undef;
    }
#  } else {
#    Log3 $hash->{NAME}, 2, "$hash->{NAME} event channel is not connected";
  }
}



1;

=pod
=begin html

<a name="TeslaCar"></a>
<h3>TeslaCar</h3>
<ul>
  <a name="TeslaCar_define"></a>
  <h4>Define</h4>
  <ul>
    <code>define &lt;name&gt; TeslaCar &lt;connection&gt; &lt;VIN&gt;</code>
    <br/>
    <br/>
    Defines a single TESLA vehicle connected to your account using the VIN (vehicle identification number). <br><br>
    Example:

    <code>define KITT TeslaCar teslaconn 5YJSA7E27HF100000</code><br>

    <br/>
	Typically the TeslaCar devices are created automatically by the scanDevices action in TeslaConnection.
    <br/>
  </ul>

  <a name="TeslaCar_set"></a>
  <b>Set</b>
  <ul>

    <li>wakeUpCar<br>
      If the car is in state 'asleep', it can be put to 'online' using this call
    </li>
    <li>flashLights<br>
      If the car is in state 'online', it will flash its headlights
    </li>
    <li>honkHorn<br>
      If the car is in state 'online', it will honk its horn
    </li>
    <li>startCharging<br>
      If the car is in state 'online' and a charger is attached, it will start charging
    </li>
    <li>stopCharging<br>
      If the car is in state 'online' a charging, it will stop charging
    </li>
    <li>startHvacSystem<br>
      If the car is in state 'online', it will start the air conditioning system
    </li>
    <li>stopHvacSystem<br>
      If the car is in state 'online', it will stop the air conditioning system
    </li>
    <li>charge_limit_soc<br>
      If the car is in state 'online', you can set the charge limit.
      Needs the new charge limit percentage as numeric argument (50-100)
    </li>
    <li>temperature<br>
      If the car is in state 'online', you can set the interior temperature for air conditioning
      Needs the new temperature as numeric argument
    </li>
    <li>init<br>
      Refresh car connection and details, normally only used internally.
    </li>
  </ul>
  <br>

  <a name="TeslaCar_Attr"></a>
  <h4>Attributes</h4>
  <ul>
    <li><a name="dataRequest"><code>attr &lt;name&gt; dataRequest &lt;String&gt;</code></a>
    <br />Data items to collect from Tesla API, the list can contain any combination of
    <br />"data","stream","vehicle","charge","drive","climate","gui"
    <br />The "stream" support is experimental and will produce a huge amount of update if the vehicle is moving.
    <br />The "data" item contains all information of vehicle, charge, drive, climate and gui
    </li>
    <li><a name="pollingTimer"><code>attr &lt;name&gt; pollingTimer &lt;Integer&gt;</code></a>
                <br />Interval for checking if the car is online, default is 1 minute</li>
    <li><a name="updateTimer"><code>attr &lt;name&gt; updateTimer &lt;Integer&gt;</code></a>
                <br />Interval for updating car data if it is not moving, default is 10 minutes</li>
    <li><a name="streamingTimer"><code>attr &lt;name&gt; streamingTimer &lt;Integer&gt;</code></a>
                <br />Interval reading stream updates, default is 1 second</li>
  </ul>
</ul>

=end html
=cut
