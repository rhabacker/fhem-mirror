########################################################################################################################
# $Id: 76_SolarForecast.pm 21735 2020-04-20 20:53:24Z DS_Starter $
#########################################################################################################################
#       76_SolarForecast.pm
#
#       (c) 2020-2022 by Heiko Maaz  e-mail: Heiko dot Maaz at t-online dot de
# 
#       This script is part of fhem.
#
#       Fhem is free software: you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation, either version 2 of the License, or
#       (at your option) any later version.
#
#       Fhem is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#########################################################################################################################
package FHEM::SolarForecast;                              ## no critic 'package'

use strict;
use warnings;
use POSIX;
use GPUtils qw(GP_Import GP_Export);                      # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
use Time::HiRes qw(gettimeofday);
eval "use FHEM::Meta;1" or my $modMetaAbsent = 1;         ## no critic 'eval'
use Encode;
use Color;
use utf8;
eval "use JSON;1;" or my $jsonabs = "JSON";               ## no critic 'eval' # Debian: apt-get install libjson-perl

use FHEM::SynoModules::SMUtils qw(
                                   evaljson  
                                   moduleVersion
                                   trim
                                 );                       # Hilfsroutinen Modul

use Data::Dumper; 
no if $] >= 5.017011, warnings => 'experimental::smartmatch';
                                 
# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import( 
      qw(
          attr
          AnalyzePerlCommand
          AttrVal
          AttrNum
          CommandAttr
          CommandSet
          CommandSetReading
          data
          defs
          delFromDevAttrList
          delFromAttrList
          devspec2array
          deviceEvents
          DoTrigger
          Debug
          fhemTimeLocal
          FmtDateTime
          FileWrite
          FileRead
          FileDelete
          FmtTime
          FW_makeImage
          getKeyValue
          init_done
          InternalTimer
          IsDisabled
          Log
          Log3            
          modules
          parseParams          
          readingsSingleUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsBeginUpdate
          readingsDelete
          readingsEndUpdate
          ReadingsNum
          ReadingsTimestamp
          ReadingsVal
          RemoveInternalTimer
          readingFnAttributes
          setKeyValue
          sortTopicNum   
          FW_cmd
          FW_directNotify
          FW_ME                                     
          FW_subdir                                 
          FW_room                                  
          FW_detail                                 
          FW_wname     
        )
  );
  
  # Export to main context with different name
  #     my $pkg  = caller(0);
  #     my $main = $pkg;
  #     $main =~ s/^(?:.+::)?([^:]+)$/main::$1\_/g;
  #     foreach (@_) {
  #         *{ $main . $_ } = *{ $pkg . '::' . $_ };
  #     }
  GP_Export(
      qw(
          Initialize
          pageAsHtml
          NexthoursVal
        )
  );  
  
}

# Versions History intern
my %vNotesIntern = (
  "0.65.1 "=> "07.07.2022  change logic of __calcEnergyPieces function and the \%hef hash ",
  "0.65.0 "=> "03.07.2022  feature key interruptable for consumer ",
  "0.64.2 "=> "23.06.2022  fix switch off by switch off condition in ___switchConsumerOff ",
  "0.64.1 "=> "07.06.2022  fixing simplifyCstate, sub ___setConsumerSwitchingState to improve safe consumer switching ",
  "0.64.0 "=> "04.06.2022  consumer type charger added, new attr createConsumptionRecReadings ",
  "0.63.2 "=> "21.05.2022  changed isConsumptionRecommended to isIntimeframe, renewed isConsumptionRecommended ",
  "0.63.1 "=> "19.05.2022  code review __switchConsumer ",
  "0.63.0 "=> "18.05.2022  new attr flowGraphicConsumerDistance ",
  "0.62.0 "=> "16.05.2022  new key 'swoffcond' in consumer attributes ",
  "0.61.0 "=> "15.05.2022  limit PV forecast to inverter capacity ",
  "0.60.1 "=> "15.05.2022  consumerHash -> new key avgruntime, don't modify mintime by avgruntime by default anymore ".
                           "debug switch conditions ",
  "0.60.0 "=> "14.05.2022  new key 'swoncond' in consumer attributes ",
  "0.59.0 "=> "01.05.2022  new attr createTomorrowPVFcReadings ",
  "0.58.0 "=> "20.04.2022  new setter consumerImmediatePlanning, functions isConsumerPhysOn isConsumerPhysOff ",
  "0.57.3 "=> "10.04.2022  some fixes (\$eavg in ___csmSpecificEpieces, useAutoCorrection switch to regex) ",
  "0.57.2 "=> "03.04.2022  area factor for 25° added ",
  "0.57.1 "=> "28.02.2022  new attr flowGraphicShowConsumerPower and flowGraphicShowConsumerRemainTime (Consumer remainTime in flowGraphic)",                                                                                                                                
  "0.56.11"=> "01.12.2021  comment: 'next if(\$surplus <= 0);' to resolve consumer planning problem if 'mode = must' and the ".
                           "current doesn't have suplus ",
  "0.56.10"=> "14.11.2021  change sub _flowGraphic (Max), https://forum.fhem.de/index.php/topic,117864.msg1186970.html#msg1186970, new reset consumerMaster ",
  "0.56.9" => "27.10.2021  change sub _flowGraphic (Max) ",
  "0.56.8" => "25.10.2021  change func  ___csmSpecificEpieces as proposed from Max : https://forum.fhem.de/index.php/topic,117864.msg1180452.html#msg1180452 ",
  "0.56.7" => "18.10.2021  new attr flowGraphicShowConsumerDummy ",
  "0.56.6" => "19.09.2021  bug fix ",
  "0.56.5" => "16.09.2021  fix sub ___csmSpecificEpieces (rows 2924-2927) ",
  "0.56.4" => "16.09.2021  new sub ___csmSpecificEpieces ",
  "0.56.3" => "15.09.2021  extent __calcEnergyPieces by MadMax calc (first test implementation) ",
  "0.56.2" => "14.09.2021  some fixes, new calculation of hourscsmeXX, new key minutescsmXX ",
  "0.56.1" => "12.09.2021  some fixes ",
  "0.56.0" => "11.09.2021  new Attr flowGraphicShowConsumer, extend calc consumer power consumption ",
  "0.55.3" => "08.09.2021  add energythreshold to etotal key ",
  "0.55.2" => "08.09.2021  minor fixes, use Color ",
  "0.55.1" => "05.09.2021  delete invalid consumer index, Forum: https://forum.fhem.de/index.php/topic,117864.msg1173219.html#msg1173219 ",
  "0.55.0" => "04.09.2021  new key pcurr for attr customerXX ",
  "0.54.5" => "29.08.2021  change metadata ",
  "0.54.4" => "12.07.2021  round Current_PV in _transferInverterValues ",
  "0.54.3" => "11.07.2021  fix _flowGraphic because of Current_AutarkyRate with powerbatout ",
  "0.54.2" => "01.07.2021  fix Current_AutarkyRate with powerbatout ",
  "0.54.1" => "23.06.2021  better log in  __weatherOnBeam ",
  "0.54.0" => "19.06.2021  new calcVariance, new reset pvCorrection circular, behavior of attr 'numHistDays', fixes ",
  "0.53.0" => "17.06.2021  Logic for preferential charging battery, attr preferredChargeBattery ",
  "0.52.5" => "16.06.2021  sub __weatherOnBeam ",
  "0.52.4" => "15.06.2021  minor fix, possible avoid implausible inverter values ",
  "0.52.3" => "14.06.2021  consumer on/off icon gray if no on/off command is defined, more consumer debug log ",
  "0.52.2" => "13.06.2021  attr consumerAdviceIcon can be 'none', new attr debug, minor fixes, write consumers cachefile ",
  "0.52.1" => "12.06.2021  change Attr Css behavior, new attr consumerAdviceIcon ",
  "0.52.0" => "12.06.2021  new Attr Css ",
  "0.51.3" => "10.06.2021  more refactoring, add 'none' to graphicSelect ",
  "0.51.2" => "05.06.2021  minor fixes ",
  "0.51.1" => "04.06.2021  minor fixes ",
  "0.51.0" => "03.06.2021  some bugfixing, Calculation of PV correction factors refined, new setter plantConfiguration ".
                           "delete getter stringConfig ",
  "0.50.2" => "02.06.2021  more refactoring, delete attr headerAlignment, consumerlegend as table ",
  "0.50.1" => "02.06.2021  switch to mathematical rounding of cloudiness range ",
  "0.50.0" => "01.06.2021  real switch off time in consumerXX_planned_stop when finished, change key 'ready' to 'auto' ".
                           "consider switch on Time limits (consumer keys notbefore/notafter) ",
  "0.49.5" => "01.06.2021  change pv correction factor to 1 if no historical factors found (only with automatic correction) ",
  "0.49.4" => "01.06.2021  fix wrong display at month change and using historyHour ",
  "0.49.3" => "31.05.2021  improve calcPVforecast pvcorrfactor for multistring configuration ",
  "0.49.2" => "31.05.2021  fix time calc in sub forecastGraphic ",
  "0.49.1" => "30.05.2021  no consumer check during start Forum: https://forum.fhem.de/index.php/topic,117864.msg1159959.html#msg1159959  ",
  "0.49.0" => "29.05.2021  consumer legend, attr consumerLegend, no negative val Current_SelfConsumption, Current_PV ",
  "0.48.0" => "28.05.2021  new optional key ready in consumer attribute ",
  "0.47.0" => "28.05.2021  add flowGraphic, attr flowGraphicSize, graphicSelect, flowGraphicAnimate ",
  "0.46.1" => "21.05.2021  set <> reset pvHistory <day> <hour> ",
  "0.46.0" => "16.05.2021  integrate intotal, outtotal to currentBatteryDev, set maxconsumer to 9 ",
  "0.45.1" => "13.05.2021  change the calc of etotal at the beginning of every hour in _transferInverterValues ".
                           "fix createNotifyDev for currentBatteryDev ",
  "0.45.0" => "12.05.2021  integrate consumptionForecast to graphic, change beamXContent to pvForecast, pvReal ",
  "0.44.0" => "10.05.2021  consumptionForecast for attr beamXContent, consumer are switched on/off ",
  "0.43.0" => "08.05.2021  plan Consumers ",
  "0.42.0" => "01.05.2021  new attr consumerXX, currentMeterDev is mandatory, new getter valConsumerMaster ".
                           "new commandref ancor syntax ",
  "0.41.0" => "28.04.2021  _estConsumptionForecast: implement Smoothing difference ",
  "0.40.0" => "25.04.2021  change checkdwdattr, new attr follow70percentRule ",
  "0.39.0" => "24.04.2021  new attr sameWeekdaysForConsfc, readings Current_SelfConsumption, Current_SelfConsumptionRate, ".
                           "Current_AutarkyRate ",
  "0.38.3" => "21.04.2021  minor fixes in sub calcVariance, Traffic light indicator for prediction quality, some more fixes ",
  "0.38.2" => "20.04.2021  fix _estConsumptionForecast, add consumption values to graphic ",
  "0.38.1" => "19.04.2021  bug fixing ",
  "0.38.0" => "18.04.2021  consumption forecast for the next hours prepared ",
  "0.37.0" => "17.04.2021  _estConsumptionForecast, new getter forecastQualities, new setter currentRadiationDev ".
                           "language sensitive setup hints ",
  "0.36.1" => "14.04.2021  add dayname to pvHistory ",
  "0.36.0" => "14.04.2021  add con to pvHistory, add quality info to pvCircular, new reading nextPolltime ",
  "0.35.0" => "12.04.2021  create additional PVforecast events - PV forecast until the end of the coming day ",
  "0.34.1" => "11.04.2021  further improvement of cloud dependent calculation autocorrection ",
  "0.34.0" => "10.04.2021  only hours with the same cloud cover range are considered for pvCorrection, some fixes ",
  "0.33.0" => "09.04.2021  new setter currentBatteryDev, bugfix in _transferMeterValues ",
  "0.32.0" => "09.04.2021  currentMeterDev can have: gcon=-gfeedin ",
  "0.31.1" => "07.04.2021  write new values to pvhistory, change CO to Current_Consumption in graphic ",
  "0.31.0" => "06.04.2021  extend currentMeterDev by gfeedin, feedtotal ",
  "0.30.0" => "05.04.2021  estimate readings to the minute in sub _calcSummaries, new setter energyH4Trigger ",
  "0.29.0" => "03.04.2021  new setter powerTrigger ",
  "0.28.0" => "03.04.2021  new attributes beam1FontColor, beam2FontColor, rename/new some readings ",
  "0.27.0" => "02.04.2021  additional readings ",
  "0.26.0" => "02.04.2021  rename attr maxPV to maxValBeam, bugfix in _specialActivities ",
  "0.25.0" => "28.03.2021  changes regarding perlcritic, new getter valCurrent ",
  "0.24.0" => "26.03.2021  the language setting of the system is taken into account in the weather texts ".
                           "rename weatherColor_night to weatherColorNight, history_hour to historyHour ",
  "0.23.0" => "25.03.2021  change attr layoutType, fix calc reading Today_PVforecast ",
  "0.22.0" => "25.03.2021  event management, move DWD values one hour to the future, some more corrections ",
  "0.21.0" => "24.03.2021  event management ",
  "0.20.0" => "23.03.2021  new sub CircularVal, NexthoursVal, some fixes ",
  "0.19.0" => "22.03.2021  new sub HistoryVal, some fixes ",
  "0.18.0" => "21.03.2021  implement sub forecastGraphic from Wzut ",
  "0.17.1" => "21.03.2021  bug fixes, delete Helper->NextHour ",
  "0.17.0" => "20.03.2021  new attr cloudFactorDamping / rainFactorDamping, fixes in Graphic sub ",
  "0.16.0" => "19.03.2021  new getter nextHours, some fixes ",
  "0.15.3" => "19.03.2021  corrected weather consideration for call calcPVforecast ",
  "0.15.2" => "19.03.2021  some bug fixing ",
  "0.15.1" => "18.03.2021  replace ThisHour_ by NextHour00_ ",
  "0.15.0" => "18.03.2021  delete overhanging readings in sub _transferDWDForecastValues ",
  "0.14.0" => "17.03.2021  new getter PVReal, weatherData, consumption total in currentMeterdev ",
  "0.13.0" => "16.03.2021  changed sub forecastGraphic from Wzut ",
  "0.12.0" => "16.03.2021  switch etoday to etotal ",
  "0.11.0" => "14.03.2021  new attr history_hour, beam1Content, beam2Content, implement sub forecastGraphic from Wzut, ".
                           "rename attr beamColor, beamColor2 , more fixes ",
  "0.10.0" => "13.03.2021  hour shifter in sub _transferMeterValues, lot of fixes ",
  "0.9.0"  => "13.03.2021  more helper hashes Forum: https://forum.fhem.de/index.php/topic,117864.msg1139251.html#msg1139251 ".
                           "cachefile pvhist is persistent ",
  "0.8.0"  => "07.03.2021  helper hash Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350 ",
  "0.7.0"  => "01.03.2021  add function DbLog_splitFn ",
  "0.6.0"  => "27.01.2021  change calcPVforecast from formula 1 to formula 2 ",
  "0.5.0"  => "25.01.2021  add multistring support, add reset inverterStrings ",
  "0.4.0"  => "24.01.2021  setter moduleDirection, add Area factor to calcPVforecast, add reset pvCorrection ",
  "0.3.0"  => "21.01.2021  add cloud correction, add rain correction, add reset pvHistory, setter writeHistory ",
  "0.2.0"  => "20.01.2021  use SMUtils, JSON, implement getter data,html,pvHistory, correct the 'disable' problem ",
  "0.1.0"  => "09.12.2020  initial Version "
);

# Voreinstellungen

my %hset = (                                                                # Hash der Set-Funktion
  consumerImmediatePlanning => { fn => \&_setconsumerImmediatePlanning },
  currentForecastDev        => { fn => \&_setcurrentForecastDev        },
  currentRadiationDev       => { fn => \&_setcurrentRadiationDev       },
  modulePeakString          => { fn => \&_setmodulePeakString          },
  inverterStrings           => { fn => \&_setinverterStrings           },
  consumerAction            => { fn => \&_setconsumerAction            },
  currentInverterDev        => { fn => \&_setinverterDevice            },
  currentMeterDev           => { fn => \&_setmeterDevice               },
  currentBatteryDev         => { fn => \&_setbatteryDevice             },
  energyH4Trigger           => { fn => \&_setenergyH4Trigger           },
  plantConfiguration        => { fn => \&_setplantConfiguration        },
  powerTrigger              => { fn => \&_setpowerTrigger              },
  pvCorrectionFactor_05     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_06     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_07     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_08     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_09     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_10     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_11     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_12     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_13     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_14     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_15     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_16     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_17     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_18     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_19     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_20     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_21     => { fn => \&_setpvCorrectionFactor        },
  pvCorrectionFactor_Auto   => { fn => \&_setpvCorrectionFactorAuto    },
  reset                     => { fn => \&_setreset                     },
  moduleTiltAngle           => { fn => \&_setmoduleTiltAngle           },
  moduleDirection           => { fn => \&_setmoduleDirection           },
  writeHistory              => { fn => \&_setwriteHistory              },
);

my %hget = (                                                                # Hash für Get-Funktion (needcred => 1: Funktion benötigt gesetzte Credentials)
  data              => { fn => \&_getdata,                   needcred => 0 },
  html              => { fn => \&_gethtml,                   needcred => 0 },
  ftui              => { fn => \&_getftui,                   needcred => 0 },
  valCurrent        => { fn => \&_getlistCurrent,            needcred => 0 },
  valConsumerMaster => { fn => \&_getlistvalConsumerMaster,  needcred => 0 },
  pvHistory         => { fn => \&_getlistPVHistory,          needcred => 0 },
  pvCircular        => { fn => \&_getlistPVCircular,         needcred => 0 },
  forecastQualities => { fn => \&_getForecastQualities,      needcred => 0 },
  nextHours         => { fn => \&_getlistNextHours,          needcred => 0 },
);

my %hattr = (                                                                # Hash für Attr-Funktion
  consumer                      => { fn => \&_attrconsumer          },
  createConsumptionRecReadings  => { fn => \&_attrcreateConsRecRdgs },
);

my %htr = (                                                                  # Hash even/odd für <tr>
  0 => { cl => 'even' },
  1 => { cl => 'odd' },
);

my %hff = (                                                                                           # Flächenfaktoren 
  "0"  => { N => 100, NE => 100, E => 100, SE => 100, S => 100, SW => 100, W => 100, NW => 100 },     # http://www.ing-büro-junge.de/html/photovoltaik.html
  "10" => { N => 90,  NE => 93,  E => 100, SE => 105, S => 107, SW => 105, W => 100, NW => 93  },
  "20" => { N => 80,  NE => 84,  E => 97,  SE => 108, S => 114, SW => 108, W => 97,  NW => 84  },
  "25" => { N => 75,  NE => 80,  E => 95,  SE => 109, S => 115, SW => 109, W => 95,  NW => 80  },
  "30" => { N => 69,  NE => 76,  E => 94,  SE => 110, S => 117, SW => 110, W => 94,  NW => 76  },
  "40" => { N => 59,  NE => 68,  E => 90,  SE => 109, S => 117, SW => 109, W => 90,  NW => 68  },
  "45" => { N => 55,  NE => 65,  E => 87,  SE => 108, S => 115, SW => 108, W => 87,  NW => 65  },
  "50" => { N => 49,  NE => 62,  E => 85,  SE => 107, S => 113, SW => 107, W => 85,  NW => 62  },
  "60" => { N => 42,  NE => 55,  E => 80,  SE => 102, S => 111, SW => 102, W => 80,  NW => 55  },
  "70" => { N => 37,  NE => 50,  E => 74,  SE => 95,  S => 104, SW => 95,  W => 74,  NW => 50  },
  "80" => { N => 35,  NE => 46,  E => 67,  SE => 86,  S => 95,  SW => 86,  W => 67,  NW => 46  },
  "90" => { N => 33,  NE => 43,  E => 62,  SE => 78,  S => 85,  SW => 78,  W => 62,  NW => 43  },
);                                                                                          

my %hqtxt = (                                                                                                 # Hash (Setup) Texte
  cfd    => { EN => qq{Please select the Weather forecast device with "set LINK currentForecastDev"}, 
              DE => qq{Bitte geben sie das Wettervorhersage Device mit "set LINK currentForecastDev" an}                },
  crd    => { EN => qq{Please select the Radiation forecast device with "set LINK currentRadiationDev"},
              DE => qq{Bitte geben sie das Strahlungsvorhersage Device mit "set LINK currentRadiationDev" an}           },
  cid    => { EN => qq{Please specify the Inverter device with "set LINK currentInverterDev"},
              DE => qq{Bitte geben sie das Wechselrichter Device mit "set LINK currentInverterDev" an}                  },
  mid    => { EN => qq{Please specify the device for energy measurement with "set LINK currentMeterDev"},
              DE => qq{Bitte geben sie das Device zur Energiemessung mit "set LINK currentMeterDev" an}                 },
  ist    => { EN => qq{Please define all of your used string names with "set LINK inverterStrings"},
              DE => qq{Bitte geben sie alle von Ihnen verwendeten Stringnamen mit "set LINK inverterStrings" an}        },
  mps    => { EN => qq{Please specify the total peak power for every string with "set LINK modulePeakString"},
              DE => qq{Bitte geben sie die Gesamtspitzenleistung von jedem String mit "set LINK modulePeakString" an}   },
  mdr    => { EN => qq{Please specify the module direction with "set LINK moduleDirection"},
              DE => qq{Bitte geben Sie die Modulausrichtung mit "set LINK moduleDirection" an}                          },
  mta    => { EN => qq{Please specify the module tilt angle with "set LINK moduleTiltAngle"},
              DE => qq{Bitte geben Sie den Modulneigungswinkel mit "set LINK moduleTiltAngle" an}                       },
  awd    => { EN => qq{Waiting for solar forecast data ...},
              DE => qq{Warten auf Solarvorhersagedaten ...}                                                             },
  cnsm   => { EN => qq{Consumer},
              DE => qq{Verbraucher}                                                                                     },
  eiau   => { EN => qq{Off/On},
              DE => qq{Aus/Ein}                                                                                         },
  auto   => { EN => qq{Auto},
              DE => qq{Auto}                                                                                            },
  pstate => { EN => qq{Planning&nbsp;status:&nbsp;<pstate><br>On:&nbsp;<start><br>Off:&nbsp;<stop>},
              DE => qq{Planungsstatus:&nbsp;<pstate><br>Ein:&nbsp;<start><br>Aus:&nbsp;<stop>}                          },
  strok  => { EN => qq{Congratulations &#128522, your string configuration checked without found errors !},
              DE => qq{Herzlichen Glückwunsch &#128522, Ihre String-Konfiguration wurde ohne gefundene Fehler geprüft!} },
  strnok => { EN => qq{Oh no &#128577, your string configuration is inconsistent.\nPlease check the settings of modulePeakString, moduleDirection, moduleTiltAngle !},
              DE => qq{Oh nein &#128577, Ihre String-Konfiguration ist inkonsistent.\nBitte überprüfen Sie die Einstellungen von modulePeakString, moduleDirection, moduleTiltAngle !}},
);

my %htitles = (                                                                                                 # Hash Hilfetexte (Mouse Over)
  iaaf     => { EN => qq{Automatic mode off -> Enable automatic mode}, 
                DE => qq{Automatikmodus aus -> Automatik freigeben}                                                },
  ieas     => { EN => qq{Automatic mode on -> Lock automatic mode},
                DE => qq{Automatikmodus ein -> Automatik sperren}                                                  },
  iave     => { EN => qq{Off -> Switch on consumer},
                DE => qq{Aus -> Verbraucher einschalten}                                                           },
  ians     => { EN => qq{Off -> no on-command defined!},
                DE => qq{Aus -> kein on-Kommando definiert!}                                                       },
  ieva     => { EN => qq{On -> Switch off consumer},
                DE => qq{Ein -> Verbraucher ausschalten}                                                           },
  iens     => { EN => qq{On -> no off-command defined!},
                DE => qq{Ein -> kein off-Kommando definiert!}                                                      },  
  upd      => { EN => qq{Update},
                DE => qq{Update}                                                                                   },
  on       => { EN => qq{switched on},
                DE => qq{eingeschaltet}                                                                            },
  off      => { EN => qq{switched off},
                DE => qq{ausgeschaltet}                                                                            },
  undef    => { EN => qq{undefined},
                DE => qq{undefiniert}                                                                              },
  dela     => { EN => qq{delayed},
                DE => qq{verzoegert}                                                                               },
  conrec   => { EN => qq{Current time is within the consumption planning},
                DE => qq{Aktuelle Zeit liegt innerhalb der Verbrauchsplanung}                                      },
  connorec => { EN => qq{Consumption planning is outside current time\n(Click for immediate planning)},
                DE => qq{Verbrauchsplanung liegt ausserhalb aktueller Zeit\n(Click f&#252;r sofortige Einplanung)} },
  pstate   => { EN => qq{Planning&nbsp;status:&nbsp;<pstate>\n\nOn:&nbsp;<start>\nOff:&nbsp;<stop>},
                DE => qq{Planungsstatus:&nbsp;<pstate>\n\nEin:&nbsp;<start>\nAus:&nbsp;<stop>}                     },
  akorron  => { EN => qq{Enable auto correction with:\nset <NAME> pvCorrectionFactor_Auto on},
                DE => qq{Einschalten Autokorrektur mit:\nset <NAME> pvCorrectionFactor_Auto on}                    },
  splus    => { EN => qq{PV surplus exists},
                DE => qq{PV-&#220;berschu&#223; ist vorhanden}                                                     },
  nosplus  => { EN => qq{no PV surplus present},
                DE => qq{kein PV-&#220;berschu&#223; vorhanden}                                                    },
);

my %weather_ids = (
  # s =>  0 , 0 - 3   DWD -> kein signifikantes Wetter
  # s =>  1 , 45 - 99 DWD -> signifikantes Wetter
  '0'   => { s => '0', icon => 'weather_sun',              txtd => 'sonnig',                                                                   txte => 'sunny'                                                                      },
  '1'   => { s => '0', icon => 'weather_cloudy_light',     txtd => 'Bewölkung abnehmend',                                                      txte => 'Cloudiness decreasing'                                                      },
  '2'   => { s => '0', icon => 'weather_cloudy',           txtd => 'Bewölkung unverändert',                                                    txte => 'Cloudiness unchanged'                                                       },
  '3'   => { s => '0', icon => 'weather_cloudy_heavy',     txtd => 'Bewölkung zunehmend',                                                      txte => 'Cloudiness increasing'                                                      },
  '4'   => { s => '0', icon => 'unknown',                  txtd => 'Sicht durch Rauch oder Asche vermindert',                                  txte => 'Visibility reduced by smoke or ash'                                         },
  '5'   => { s => '0', icon => 'unknown',                  txtd => 'trockener Dunst (relative Feuchte < 80 %)',                                txte => 'dry haze (relative humidity < 80 %)'                                        },
  '6'   => { s => '0', icon => 'unknown',                  txtd => 'verbreiteter Schwebstaub, nicht vom Wind herangeführt',                    txte => 'widespread airborne dust, not brought in by the wind'                       },
  '7'   => { s => '0', icon => 'unknown',                  txtd => 'Staub oder Sand bzw. Gischt, vom Wind herangeführt',                       txte => 'Dust or sand or spray, brought in by the wind'                              },
  '8'   => { s => '0', icon => 'unknown',                  txtd => 'gut entwickelte Staub- oder Sandwirbel',                                   txte => 'well-developed dust or sand vortex'                                         },
  '9'   => { s => '0', icon => 'unknown',                  txtd => 'Staub- oder Sandsturm im Gesichtskreis, aber nicht an der Station',        txte => 'Dust or sand storm in the visual circle, but not at the station'            },

  '10'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel',                                                                    txte => 'Fog'                                                                        },
  '11'  => { s => '0', icon => 'weather_rain_fog',         txtd => 'Nebel mit Regen',                                                          txte => 'Fog with rain'                                                              },
  '12'  => { s => '0', icon => 'weather_fog',              txtd => 'durchgehender Bodennebel',                                                 txte => 'continuous ground fog'                                                      },
  '13'  => { s => '0', icon => 'unknown',                  txtd => 'Wetterleuchten sichtbar, kein Donner gehört',                              txte => 'Weather light visible, no thunder heard'                                    },
  '14'  => { s => '0', icon => 'unknown',                  txtd => 'Niederschlag im Gesichtskreis, nicht den Boden erreichend',                txte => 'Precipitation in the visual circle, not reaching the ground'                },
  '15'  => { s => '0', icon => 'unknown',                  txtd => 'Niederschlag in der Ferne (> 5 km), aber nicht an der Station',            txte => 'Precipitation in the distance (> 5 km), but not at the station'             },
  '16'  => { s => '0', icon => 'unknown',                  txtd => 'Niederschlag in der Nähe (< 5 km), aber nicht an der Station',             txte => 'Precipitation in the vicinity (< 5 km), but not at the station'             },
  '17'  => { s => '0', icon => 'unknown',                  txtd => 'Gewitter (Donner hörbar), aber kein Niederschlag an der Station',          txte => 'Thunderstorm (thunder audible), but no precipitation at the station'        },
  '18'  => { s => '0', icon => 'unknown',                  txtd => 'Markante Böen im Gesichtskreis, aber kein Niederschlag an der Station',    txte => 'marked gusts in the visual circle, but no precipitation at the station'     },
  '19'  => { s => '0', icon => 'unknown',                  txtd => 'Tromben (trichterförmige Wolkenschläuche) im Gesichtskreis',               txte => 'Trombles (funnel-shaped cloud tubes) in the circle of vision'               },

  '20'  => { s => '0', icon => 'unknown',                  txtd => 'nach Sprühregen oder Schneegriesel',                                       txte => 'after drizzle or snow drizzle'                                              },
  '21'  => { s => '0', icon => 'unknown',                  txtd => 'nach Regen',                                                               txte => 'after rain'                                                                 },
  '22'  => { s => '0', icon => 'unknown',                  txtd => 'nach Schnefall',                                                           txte => 'after snowfall'                                                             },
  '23'  => { s => '0', icon => 'unknown',                  txtd => 'nach Schneeregen oder Eiskörnern',                                         txte => 'after sleet or ice grains'                                                  },
  '24'  => { s => '0', icon => 'unknown',                  txtd => 'nach gefrierendem Regen',                                                  txte => 'after freezing rain'                                                        },
  '25'  => { s => '0', icon => 'unknown',                  txtd => 'nach Regenschauer',                                                        txte => 'after rain shower'                                                          },
  '26'  => { s => '0', icon => 'unknown',                  txtd => 'nach Schneeschauer',                                                       txte => 'after snow shower'                                                          },
  '27'  => { s => '0', icon => 'unknown',                  txtd => 'nach Graupel- oder Hagelschauer',                                          txte => 'after sleet or hail showers'                                                },
  '28'  => { s => '0', icon => 'unknown',                  txtd => 'nach Nebel',                                                               txte => 'after fog'                                                                  },
  '29'  => { s => '0', icon => 'unknown',                  txtd => 'nach Gewitter',                                                            txte => 'after thunderstorm'                                                         },

  '30'  => { s => '0', icon => 'unknown',                  txtd => 'leichter oder mäßiger Sandsturm, an Intensität abnehmend',                 txte => 'light or moderate sandstorm, decreasing in intensity'                       },
  '31'  => { s => '0', icon => 'unknown',                  txtd => 'leichter oder mäßiger Sandsturm, unveränderte Intensität',                 txte => 'light or moderate sandstorm, unchanged intensity'                           },
  '32'  => { s => '0', icon => 'unknown',                  txtd => 'leichter oder mäßiger Sandsturm, an Intensität zunehmend',                 txte => 'light or moderate sandstorm, increasing in intensity'                       },
  '33'  => { s => '0', icon => 'unknown',                  txtd => 'schwerer Sandsturm, an Intensität abnehmend',                              txte => 'heavy sandstorm, decreasing in intensity'                                   },
  '34'  => { s => '0', icon => 'unknown',                  txtd => 'schwerer Sandsturm, unveränderte Intensität',                              txte => 'heavy sandstorm, unchanged intensity'                                       },
  '35'  => { s => '0', icon => 'unknown',                  txtd => 'schwerer Sandsturm, an Intensität zunehmend',                              txte => 'heavy sandstorm, increasing in intensity'                                   },
  '36'  => { s => '0', icon => 'weather_snow_light',       txtd => 'leichtes oder mäßiges Schneefegen, unter Augenhöhe',                       txte => 'light or moderate snow sweeping, below eye level'                           },
  '37'  => { s => '0', icon => 'weather_snow_heavy',       txtd => 'starkes Schneefegen, unter Augenhöhe',                                     txte => 'heavy snow sweeping, below eye level'                                       },
  '38'  => { s => '0', icon => 'weather_snow_light',       txtd => 'leichtes oder mäßiges Schneetreiben, über Augenhöhe',                      txte => 'light or moderate blowing snow, above eye level'                            },
  '39'  => { s => '0', icon => 'weather_snow_heavy',       txtd => 'starkes Schneetreiben, über Augenhöhe',                                    txte => 'heavy snow drifting, above eye level'                                       },

  '40'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel in einiger Entfernung',                                              txte => 'Fog in some distance'                                                       },
  '41'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel in Schwaden oder Bänken',                                            txte => 'Fog in swaths or banks'                                                     },
  '42'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel, Himmel erkennbar, dünner werdend',                                  txte => 'Fog, sky recognizable, thinning'                                            },
  '43'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel, Himmel nicht erkennbar, dünner werdend',                            txte => 'Fog, sky not recognizable, thinning'                                        },
  '44'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel, Himmel erkennbar, unverändert',                                     txte => 'Fog, sky recognizable, unchanged'                                           },
  '45'  => { s => '1', icon => 'weather_fog',              txtd => 'Nebel',                                                                    txte => 'Fog'                                                                        },
  '46'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel, Himmel erkennbar, dichter werdend',                                 txte => 'Fog, sky recognizable, becoming denser'                                     },
  '47'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel, Himmel nicht erkennbar, dichter werdend',                           txte => 'Fog, sky not visible, becoming denser'                                      },
  '48'  => { s => '1', icon => 'weather_fog',              txtd => 'Nebel mit Reifbildung',                                                    txte => 'Fog with frost formation'                                                   },
  '49'  => { s => '0', icon => 'weather_fog',              txtd => 'Nebel mit Reifansatz, Himmel nicht erkennbar',                             txte => 'Fog with frost, sky not visible'                                            },

  '50'  => { s => '0', icon => 'weather_rain',             txtd => 'unterbrochener leichter Sprühregen',                                       txte => 'intermittent light drizzle'                                                 },
  '51'  => { s => '1', icon => 'weather_rain_light',       txtd => 'leichter Sprühregen',                                                      txte => 'light drizzle'                                                              },
  '52'  => { s => '0', icon => 'weather_rain',             txtd => 'unterbrochener mäßiger Sprühregen',                                        txte => 'intermittent moderate drizzle'                                              },
  '53'  => { s => '1', icon => 'weather_rain_light',       txtd => 'leichter Sprühregen',                                                      txte => 'light drizzle'                                                              },
  '54'  => { s => '0', icon => 'weather_rain_heavy',       txtd => 'unterbrochener starker Sprühregen',                                        txte => 'intermittent heavy drizzle'                                                 },
  '55'  => { s => '1', icon => 'weather_rain_heavy',       txtd => 'starker Sprühregen',                                                       txte => 'heavy drizzle'                                                              },
  '56'  => { s => '1', icon => 'weather_rain_light',       txtd => 'leichter gefrierender Sprühregen',                                         txte => 'light freezing drizzle'                                                     },
  '57'  => { s => '1', icon => 'weather_rain_heavy',       txtd => 'mäßiger oder starker gefrierender Sprühregen',                             txte => 'moderate or heavy freezing drizzle'                                         },
  '58'  => { s => '0', icon => 'weather_rain_light',       txtd => 'leichter Sprühregen mit Regen',                                            txte => 'light drizzle with rain'                                                    },
  '59'  => { s => '0', icon => 'weather_rain_heavy',       txtd => 'mäßiger oder starker Sprühregen mit Regen',                                txte => 'moderate or heavy drizzle with rain'                                        },

  '60'  => { s => '0', icon => 'weather_rain_light',       txtd => 'unterbrochener leichter Regen oder einzelne Regentropfen',                 txte => 'intermittent light rain or single raindrops'                                },
  '61'  => { s => '1', icon => 'weather_rain_light',       txtd => 'leichter Regen',                                                           txte => 'light rain'                                                                 },
  '62'  => { s => '0', icon => 'weather_rain',             txtd => 'unterbrochener mäßiger Regen',                                             txte => 'intermittent moderate rain'                                                 },
  '63'  => { s => '1', icon => 'weather_rain',             txtd => 'mäßiger Regen',                                                            txte => 'moderate rain'                                                              },
  '64'  => { s => '0', icon => 'weather_rain_heavy',       txtd => 'unterbrochener starker Regen',                                             txte => 'intermittent heavy rain'                                                    },
  '65'  => { s => '1', icon => 'weather_rain_heavy',       txtd => 'starker Regen',                                                            txte => 'heavy rain'                                                                 },
  '66'  => { s => '1', icon => 'weather_rain_snow_light',  txtd => 'leichter gefrierender Regen',                                              txte => 'light freezing rain'                                                        },
  '67'  => { s => '1', icon => 'weather_rain_snow_heavy',  txtd => 'mäßiger oder starker gefrierender Regen',                                  txte => 'moderate or heavy freezing rain'                                            },
  '68'  => { s => '0', icon => 'weather_rain_snow_light',  txtd => 'leichter Schneeregen',                                                     txte => 'light sleet'                                                                },
  '69'  => { s => '0', icon => 'weather_rain_snow_heavy',  txtd => 'mäßiger oder starker Schneeregen',                                         txte => 'moderate or heavy sleet'                                                    },

  '70'  => { s => '0', icon => 'weather_snow_light',       txtd => 'unterbrochener leichter Schneefall oder einzelne Schneeflocken',           txte => 'intermittent light snowfall or single snowflakes'                           },
  '71'  => { s => '1', icon => 'weather_snow_light',       txtd => 'leichter Schneefall',                                                      txte => 'light snowfall'                                                             },
  '72'  => { s => '0', icon => 'weather_snow',             txtd => 'unterbrochener mäßiger Schneefall',                                        txte => 'intermittent moderate snowfall'                                             },
  '73'  => { s => '1', icon => 'weather_snow',             txtd => 'mäßiger Schneefall',                                                       txte => 'moderate snowfall'                                                          },
  '74'  => { s => '0', icon => 'weather_snow_heavy',       txtd => 'unterbrochener starker Schneefall',                                        txte => 'intermittent heavy snowfall'                                                },
  '75'  => { s => '1', icon => 'weather_snow_heavy',       txtd => 'starker Schneefall',                                                       txte => 'heavy snowfall'                                                             },
  '76'  => { s => '0', icon => 'weather_frost',            txtd => 'Eisnadeln (Polarschnee)',                                                  txte => 'Ice needles (polar snow)'                                                   },
  '77'  => { s => '1', icon => 'weather_frost',            txtd => 'Schneegriesel',                                                            txte => 'Snow drizzle'                                                               },
  '78'  => { s => '0', icon => 'weather_frost',            txtd => 'Schneekristalle',                                                          txte => 'Snow crystals'                                                              },
  '79'  => { s => '0', icon => 'weather_frost',            txtd => 'Eiskörner (gefrorene Regentropfen)',                                       txte => 'Ice grains (frozen raindrops)'                                              },

  '80'  => { s => '1', icon => 'weather_rain_light',       txtd => 'leichter Regenschauer',                                                    txte => 'light rain shower'                                                          },
  '81'  => { s => '1', icon => 'weather_rain',             txtd => 'mäßiger oder starkerRegenschauer',                                         txte => 'moderate or heavy rain shower'                                              },
  '82'  => { s => '1', icon => 'weather_rain_heavy',       txtd => 'sehr starker Regenschauer',                                                txte => 'very heavy rain shower'                                                     },
  '83'  => { s => '0', icon => 'weather_snow',             txtd => 'mäßiger oder starker Schneeregenschauer',                                  txte => 'moderate or heavy sleet shower'                                             },
  '84'  => { s => '0', icon => 'weather_snow_light',       txtd => 'leichter Schneeschauer',                                                   txte => 'light snow shower'                                                          },
  '85'  => { s => '1', icon => 'weather_snow_light',       txtd => 'leichter Schneeschauer',                                                   txte => 'light snow shower'                                                          },
  '86'  => { s => '1', icon => 'weather_snow_heavy',       txtd => 'mäßiger oder starker Schneeschauer',                                       txte => 'moderate or heavy snow shower'                                              },
  '87'  => { s => '0', icon => 'weather_snow_heavy',       txtd => 'mäßiger oder starker Graupelschauer',                                      txte => 'moderate or heavy sleet shower'                                             },
  '88'  => { s => '0', icon => 'unknown',                  txtd => 'leichter Hagelschauer',                                                    txte => 'light hailstorm'                                                            },
  '89'  => { s => '0', icon => 'unknown',                  txtd => 'mäßiger oder starker Hagelschauer',                                        txte => 'moderate or heavy hailstorm'                                                },

  '90'  => { s => '0', icon => 'weather_thunderstorm',     txtd => '',                                                                         txte => ''                                                                           },
  '91'  => { s => '0', icon => 'weather_storm',            txtd => '',                                                                         txte => ''                                                                           },
  '92'  => { s => '0', icon => 'weather_thunderstorm',     txtd => '',                                                                         txte => ''                                                                           },
  '93'  => { s => '0', icon => 'weather_thunderstorm',     txtd => '',                                                                         txte => ''                                                                           },
  '94'  => { s => '0', icon => 'weather_thunderstorm',     txtd => '',                                                                         txte => ''                                                                           },
  '95'  => { s => '1', icon => 'weather_thunderstorm',     txtd => 'leichtes oder mäßiges Gewitter ohne Graupel oder Hagel',                   txte => 'light or moderate thunderstorm without sleet or hail'                       },
  '96'  => { s => '1', icon => 'weather_storm',            txtd => 'starkes Gewitter ohne Graupel oder Hagel,Gewitter mit Graupel oder Hagel', txte => 'strong thunderstorm without sleet or hail,thunderstorm with sleet or hail'  },
  '97'  => { s => '0', icon => 'weather_storm',            txtd => 'starkes Gewitter mit Regen oder Schnee',                                   txte => 'heavy thunderstorm with rain or snow'                                       },
  '98'  => { s => '0', icon => 'weather_storm',            txtd => 'starkes Gewitter mit Sandsturm',                                           txte => 'strong thunderstorm with sandstorm'                                         },
  '99'  => { s => '1', icon => 'weather_storm',            txtd => 'starkes Gewitter mit Graupel oder Hagel',                                  txte => 'strong thunderstorm with sleet or hail'                                     },
  '100' => { s => '0', icon => 'weather_night',            txtd => 'sternenklarer Himmel',                                                     txte => 'starry sky'                                                                 },
);

my @chours       = (5..21);                                                       # Stunden des Tages mit möglichen Korrekturwerten                              
my $defpvme      = 16.52;                                                         # default Wirkungsgrad Solarmodule
my $definve      = 98.3;                                                          # default Wirkungsgrad Wechselrichter
my $kJtokWh      = 0.00027778;                                                    # Umrechnungsfaktor kJ in kWh
my $defmaxvar    = 0.5;                                                           # max. Varianz pro Tagesberechnung Autokorrekturfaktor
my $definterval  = 70;                                                            # Standard Abfrageintervall
my $defslidenum  = 3;                                                             # max. Anzahl der Arrayelemente in Schieberegistern

my $pvhcache     = $attr{global}{modpath}."/FHEM/FhemUtils/PVH_SolarForecast_";   # Filename-Fragment für PV History (wird mit Devicename ergänzt)
my $pvccache     = $attr{global}{modpath}."/FHEM/FhemUtils/PVC_SolarForecast_";   # Filename-Fragment für PV Circular (wird mit Devicename ergänzt)
my $plantcfg     = $attr{global}{modpath}."/FHEM/FhemUtils/PVCfg_SolarForecast_"; # Filename-Fragment für PV Anlagenkonfiguration (wird mit Devicename ergänzt)
my $csmcache     = $attr{global}{modpath}."/FHEM/FhemUtils/PVCsm_SolarForecast_"; # Filename-Fragment für Consumer Status (wird mit Devicename ergänzt)

my $calcmaxd     = 30;                                                            # Anzahl Tage die zur Berechnung Vorhersagekorrektur verwendet werden
my @dweattrmust  = qw(TTT Neff R101 ww SunUp SunRise SunSet);                     # Werte die im Attr forecastProperties des Weather-DWD_Opendata Devices mindestens gesetzt sein müssen
my @draattrmust  = qw(Rad1h);                                                     # Werte die im Attr forecastProperties des Radiation-DWD_Opendata Devices mindestens gesetzt sein müssen
my $whistrepeat  = 900;                                                           # Wiederholungsintervall Schreiben historische Daten

my $cldampdef    = 35;                                                            # Dämpfung (%) des Korrekturfaktors bzgl. effektiver Bewölkung, siehe: https://www.energie-experten.org/erneuerbare-energien/photovoltaik/planung/sonnenstunden
my $cloud_base   = 0;                                                             # Fußpunktverschiebung bzgl. effektiver Bewölkung 

my $rdampdef     = 10;                                                            # Dämpfung (%) des Korrekturfaktors bzgl. Niederschlag (R101)
my $rain_base    = 0;                                                             # Fußpunktverschiebung bzgl. effektiver Bewölkung 

my $maxconsumer  = 9;                                                             # maximale Anzahl der möglichen Consumer (Attribut) 
my $epiecHCounts = 10;                                                            # Anzahl Werte für verbraucherspezifische Energiestück Ermittlung
my @ctypes       = qw(dishwasher dryer washingmachine heater charger other);      # erlaubte Consumer Typen
my $defmintime   = 60;                                                            # default min. Einschalt- bzw. Zykluszeit in Minuten
my $defctype     = "other";                                                       # default Verbrauchertyp
my $defcmode     = "can";                                                         # default Planungsmode der Verbraucher
my $caicondef    = 'clock@gold';                                                  # default consumerAdviceIcon

my $defflowGSize = 300;                                                           # default flowGraphicSize
my $defpopercent = 0.5;                                                           # Standard % aktuelle Leistung an nominaler Leistung gemäß Typenschild

                                                                                  # Default CSS-Style
my $cssdef       = qq{.flowg.text           { stroke: none; fill: gray; font-size: 32px;}                                    \n}.
                   qq{.flowg.sun_active     { stroke: orange; fill: orange; }                                                \n}.
                   qq{.flowg.sun_inactive   { stroke: gray; fill: gray; }                                                    \n}.
                   qq{.flowg.bat25          { stroke: red; fill: red; }                                                      \n}.
                   qq{.flowg.bat50          { stroke: yellow; fill: yellow; }                                                \n}.
                   qq{.flowg.bat75          { stroke: green; fill: green; }                                                  \n}.
                   qq{.flowg.grid_color1    { fill: green; }                                                                 \n}.
                   qq{.flowg.grid_color2    { fill: red; }                                                                   \n}.
                   qq{.flowg.grid_color3    { fill: gray; }                                                                  \n}.
                   qq{.flowg.inactive_in    { stroke: gray;   stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.2; }   \n}.
                   qq{.flowg.inactive_out   { stroke: gray;   stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.2; }   \n}.
                   qq{.flowg.active_in      { stroke: red;    stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.8; animation: dash 0.5s linear; animation-iteration-count: infinite; } \n}.
                   qq{.flowg.active_out     { stroke: yellow; stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.8; animation: dash 0.5s linear; animation-iteration-count: infinite; } \n}.
                   qq{.flowg.active_bat_in  { stroke: yellow; stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.8; animation: dash 0.5s linear; animation-iteration-count: infinite; } \n}.
                   qq{.flowg.active_bat_out { stroke: green;  stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.8; animation: dash 0.5s linear; animation-iteration-count: infinite; } \n}
                   ;

my %hef = (                                                                      # Energiedaktoren für Verbrauchertypen
  "heater"         => { f => 1.00, m => 1.00, l => 1.00, mt => 240         },     
  "other"          => { f => 1.00, m => 1.00, l => 1.00, mt => $defmintime },    # f   = Faktor Energieverbrauch in erster Stunde
  "charger"        => { f => 1.00, m => 1.00, l => 1.00, mt => 120         },    # m   = Faktor Energieverbrauch zwischen erster und letzter Stunde
  "dishwasher"     => { f => 0.45, m => 0.10, l => 0.45, mt => 180         },    # l   = Faktor Energieverbrauch in letzter Stunde
  "dryer"          => { f => 0.40, m => 0.40, l => 0.20, mt => 90          },    # mt  = default mintime (Minuten)
  "washingmachine" => { f => 0.30, m => 0.40, l => 0.30, mt => 120         },    
);                                                                               

# Information zu verwendeten internen Datenhashes
# $data{$type}{$name}{circular}                                                  # Ringspeicher
# $data{$type}{$name}{current}                                                   # current values
# $data{$type}{$name}{pvhist}                                                    # historische Werte       
# $data{$type}{$name}{nexthours}                                                 # NextHours Werte
# $data{$type}{$name}{consumers}                                                 # Consumer Hash
# $data{$type}{$name}{strings}                                                   # Stringkonfiguration

################################################################
#               Init Fn
################################################################
sub Initialize {
  my $hash = shift;

  my $fwd = join ",", devspec2array("TYPE=FHEMWEB:FILTER=STATE=Initialized");
  my $hod = join ",", map { sprintf "%02d", $_} (01..24);        
  
  my ($consumer,@allc);
  for my $c (1..$maxconsumer) {
      $c         = sprintf "%02d", $c;
      $consumer .= "consumer${c}:textField-long ";
      push @allc, $c;
  }
  
  my $allcs = join ",", @allc; 
  
  $hash->{DefFn}              = \&Define;
  $hash->{UndefFn}            = \&Undef;
  $hash->{GetFn}              = \&Get;
  $hash->{SetFn}              = \&Set;
  $hash->{DeleteFn}           = \&Delete;
  $hash->{FW_summaryFn}       = \&FwFn;
  $hash->{FW_detailFn}        = \&FwFn;
  $hash->{ShutdownFn}         = \&Shutdown;
  $hash->{DbLog_splitFn}      = \&DbLogSplit;
  $hash->{AttrFn}             = \&Attr;
  $hash->{NotifyFn}           = \&Notify;
  $hash->{AttrList}           = "autoRefresh:selectnumbers,120,0.2,1800,0,log10 ".
                                "autoRefreshFW:$fwd ".
                                "beam1Color:colorpicker,RGB ".
                                "beam1Content:pvForecast,pvReal,gridconsumption,consumptionForecast ".
                                "beam1FontColor:colorpicker,RGB ".
                                "beam2Color:colorpicker,RGB ".
                                "beam2Content:pvForecast,pvReal,gridconsumption,consumptionForecast ".
                                "beam2FontColor:colorpicker,RGB ".
                                "beamHeight ".
                                "beamWidth ".
                                "cloudFactorDamping:slider,0,1,100 ".
                                "consumerLegend:none,icon_top,icon_bottom,text_top,text_bottom ".
                                "consumerAdviceIcon ".
                                "createTomorrowPVFcReadings:multiple-strict,$hod ".
                                "createConsumptionRecReadings:multiple-strict,$allcs ".
                                "Css:textField-long ".
                                "debug:1,0 ".
                                "disable:1,0 ".
                                "flowGraphicSize ".
                                "flowGraphicAnimate:1,0 ".
                                "flowGraphicConsumerDistance:slider,80,10,500 ".
                                "flowGraphicShowConsumer:1,0 ".
                                "flowGraphicShowConsumerDummy:1,0 ".      
                                "flowGraphicShowConsumerPower:0,1 ". 
                                "flowGraphicShowConsumerRemainTime:0,1 ".                                                                                 
                                "follow70percentRule:1,dynamic,0 ".
                                "forcePageRefresh:1,0 ".
                                "graphicSelect:both,flow,forecast,none ".                                     
                                "headerDetail:all,co,pv,pvco,statusLink ".
                                "historyHour:slider,-23,-1,0 ".
                                "hourCount:slider,4,1,24 ".                                                                
                                "hourStyle ".
                                "htmlStart ".
                                "htmlEnd ".
                                "interval ".
                                "layoutType:single,double,diff ".
                                "maxVariancePerDay ".
                                "maxValBeam ".
                                "numHistDays:slider,1,1,30 ".
                                "preferredChargeBattery:slider,0,1,100 ".
                                "rainFactorDamping:slider,0,1,100 ".
                                "sameWeekdaysForConsfc:1,0 ".
                                "showDiff:no,top,bottom ".
                                "showHeader:1,0 ".
                                "showLink:1,0 ".
                                "showNight:1,0 ".
                                "showWeather:1,0 ".
                                "spaceSize ".
                                "Wh/kWh:Wh,kWh ".
                                "weatherColor:colorpicker,RGB ".
                                "weatherColorNight:colorpicker,RGB ".
                                $consumer.                                
                                $readingFnAttributes;

  $hash->{FW_hideDisplayName} = 1;                     # Forum 88667

  # $hash->{FW_addDetailToSummary} = 1;
  # $hash->{FW_atPageEnd} = 1;                         # wenn 1 -> kein Longpoll ohne informid in HTML-Tag

  eval { FHEM::Meta::InitMod( __FILE__, $hash ) };     ## no critic 'eval'
 
return; 
}

###############################################################
#                  SolarForecast Define
###############################################################
sub Define {
  my ($hash, $def) = @_;

  my @a = split(/\s+/x, $def);
  
  return "Error: Perl module ".$jsonabs." is missing. Install it on Debian with: sudo apt-get install libjson-perl" if($jsonabs);

  my $name                       = $hash->{NAME};
  my $type                       = $hash->{TYPE};
  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                           # Modul Meta.pm nicht vorhanden
  
  my $params = {
      hash        => $hash,
      notes       => \%vNotesIntern,
      useAPI      => 0,
      useSMUtils  => 1,
      useErrCodes => 0
  };
  use version 0.77; our $VERSION = moduleVersion ($params);                        # Versionsinformationen setzen

  createNotifyDev ($hash);
  
  $params->{file}       = $pvhcache.$name;                                         # Cache File PV History lesen wenn vorhanden
  $params->{cachename}  = "pvhist";
  _readCacheFile ($params);

  $params->{file}       = $pvccache.$name;                                         # Cache File PV Circular lesen wenn vorhanden
  $params->{cachename}  = "circular";
  _readCacheFile ($params);  
  
  $params->{file}       = $csmcache.$name;                                         # Cache File Consumer lesen wenn vorhanden
  $params->{cachename}  = "consumers";
  _readCacheFile ($params);
    
  readingsSingleUpdate($hash, "state", "initialized", 1);

  centralTask   ($hash);                                                                                 # Einstieg in Abfrage 
  InternalTimer (gettimeofday()+$whistrepeat, "FHEM::SolarForecast::periodicWriteCachefiles", $hash, 0); # Einstieg periodisches Schreiben historische Daten
  
return;
}

################################################################
#                   Cachefile lesen
################################################################
sub _readCacheFile {               
  my $paref     = shift;
  my $hash      = $paref->{hash};
  my $file      = $paref->{file};
  my $cachename = $paref->{cachename};
  
  my $name      = $hash->{NAME};

  my ($error, @content) = FileRead ($file);                                        
  
  if(!$error) {
      my $json    = join "", @content;
      my $success = evaljson ($hash, $json);                               
      
      if($success) {
           $data{$hash->{TYPE}}{$name}{$cachename} = decode_json ($json);
           Log3($name, 3, qq{$name - SolarForecast cache "$cachename" restored});
      }
      else {
          Log3($name, 2, qq{$name - WARNING - The content of file "$file" is not readable and may be corrupt});
      }
  }
      
return;
}

###############################################################
#                  SolarForecast Set
###############################################################
sub Set {                             
  my ($hash, @a) = @_;
  return "\"set X\" needs at least an argument" if ( @a < 2 );
  my $name  = shift @a;
  my $opt   = shift @a;
  my @args  = @a;
  my $arg   = join " ", map { my $p = $_; $p =~ s/\s//xg; $p; } @a;     ## no critic 'Map blocks'
  my $prop  = shift @a;
  my $prop1 = shift @a;
  my $prop2 = shift @a;
  
  return if(IsDisabled($name));
  
  my ($setlist,@fcdevs,@cfs,@condevs);
  my ($fcd,$ind,$med,$cf,$cons) = ("","","","","noArg");
  
  my @re = qw( ConsumerMaster
               consumerPlanning
               currentBatteryDev 
               currentForecastDev
               currentInverterDev
               currentMeterDev
               energyH4Trigger
               inverterStrings
               powerTrigger
               pvCorrection
               pvHistory
             );
  my $resets = join ",",@re; 
  
  @fcdevs = devspec2array("TYPE=DWD_OpenData");
  $fcd    = join ",", @fcdevs if(@fcdevs);

  for my $h (@chours) {
      push @cfs, "pvCorrectionFactor_".sprintf("%02d",$h); 
  }
  $cf = join " ", @cfs if(@cfs);
  
  my $type  = $hash->{TYPE};
  
  for my $c (sort{$a<=>$b} keys %{$data{$type}{$name}{consumers}}) {
      push @condevs, $c if($c);
  }
  $cons = join ",", @condevs if(@condevs); 

  $setlist = "Unknown argument $opt, choose one of ".
             "consumerImmediatePlanning:$cons ".
             "currentForecastDev:$fcd ".
             "currentRadiationDev:$fcd ".
             "currentBatteryDev:textField-long ".
             "currentInverterDev:textField-long ".
             "currentMeterDev:textField-long ".
             "energyH4Trigger:textField-long ".
             "inverterStrings ".
             "modulePeakString ".
             "moduleTiltAngle ".
             "moduleDirection ".
             "plantConfiguration:check,save,restore ".
             "powerTrigger:textField-long ".
             "pvCorrectionFactor_Auto:on,off ".
             "reset:$resets ".
             "writeHistory:noArg ".
             $cf
             ;
            
  my $params = {
      hash    => $hash,
      name    => $name,
      type    => $type,
      opt     => $opt,
      arg     => $arg,
      argsref => \@args,
      prop    => $prop,
      prop1   => $prop1,
      prop2   => $prop2
  };
    
  if($hset{$opt} && defined &{$hset{$opt}{fn}}) {
      my $ret = q{};
      $ret    = &{$hset{$opt}{fn}} ($params); 
      return $ret;
  }

return "$setlist";
}

################################################################
#                      Setter consumerImmediatePlanning
################################################################
sub _setconsumerImmediatePlanning {      ## no critic "not used"
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $type    = $paref->{type};
  my $opt     = $paref->{opt};
  my $arg     = $paref->{arg};
  
  my ($c,$noTaskcall) = split " ", $arg;
  
  return qq{no consumer number specified} if(!$c);
  return qq{no valid consumer id "$c"}    if(!ConsumerVal ($hash, $c, "name", ""));  

  my $startts  = time;  
  my $mintime  = ConsumerVal ($hash, $c, "mintime", $defmintime);
  my $stopdiff = ceil        ($mintime * 60);  
  my $stopts   = $startts + $stopdiff;                                      
  
  $paref->{consumer} = $c;
  $paref->{ps}       = "planned:";
  $paref->{startts}  = $startts;                                                # Unix Timestamp für geplanten Switch on
  $paref->{stopts}   = $stopts;                                                 # Unix Timestamp für geplanten Switch off

  ___setConsumerPlanningState ($paref);
  
  my $planstate = ConsumerVal ($hash, $c, "planstate", "");
  my $calias    = ConsumerVal ($hash, $c, "alias",     "");
  
  writeDataToFile ($hash, "consumers", $csmcache.$name);                        # Cache File Consumer schreiben
  
  Log3 ($name, 3, qq{$name - Consumer "$calias" $planstate}) if($planstate);

  centralTask ($hash) if(!$noTaskcall);
  
return;
}

################################################################
#                      Setter currentForecastDev
################################################################
sub _setcurrentForecastDev {              ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop} // return qq{no forecast device specified};

  if(!$defs{$prop} || $defs{$prop}{TYPE} ne "DWD_OpenData") {
      return qq{The device "$prop" doesn't exist or has no TYPE "DWD_OpenData"};                      #' :)
  }

  readingsSingleUpdate($hash, "currentForecastDev", $prop, 1);
  createNotifyDev     ($hash);
  writeDataToFile     ($hash, "plantconfig", $plantcfg.$name);             # Anlagenkonfiguration File schreiben

return;
}

################################################################
#                      Setter currentRadiationDev
################################################################
sub _setcurrentRadiationDev {              ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop} // return qq{no radiation device specified};

  if(!$defs{$prop} || $defs{$prop}{TYPE} ne "DWD_OpenData") {
      return qq{The device "$prop" doesn't exist or has no TYPE "DWD_OpenData"};                      #' :)
  }

  readingsSingleUpdate($hash, "currentRadiationDev", $prop, 1);
  createNotifyDev     ($hash);
  writeDataToFile     ($hash, "plantconfig", $plantcfg.$name);             # Anlagenkonfiguration File schreiben

return;
}

################################################################
#                      Setter currentInverterDev
################################################################
sub _setinverterDevice {                 ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $arg   = $paref->{arg};

  if(!$arg) {
      return qq{The command "$opt" needs an argument !};
  }
  
  my ($a,$h) = parseParams ($arg);
  my $indev  = $a->[0] // "";
  
  if(!$indev || !$defs{$indev}) {
      return qq{The device "$indev" doesn't exist!};
  }
  
  if(!$h->{pv} || !$h->{etotal}) {
      return qq{The syntax of "$opt" is not correct. Please consider the commandref.};
  }  

  readingsSingleUpdate($hash, "currentInverterDev", $arg, 1);
  createNotifyDev     ($hash);
  writeDataToFile     ($hash, "plantconfig", $plantcfg.$name);             # Anlagenkonfiguration File schreiben

return;
}

################################################################
#                      Setter inverterStrings
################################################################
sub _setinverterStrings {                ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop} // return qq{no inverter strings specified};

  readingsSingleUpdate($hash, "inverterStrings", $prop,    1);
  writeDataToFile     ($hash, "plantconfig", $plantcfg.$name);             # Anlagenkonfiguration File schreiben
  
return qq{REMINDER - After setting or changing "inverterStrings" please check / set all module parameter (e.g. moduleTiltAngle) again !};
}

################################################################
#                      Setter currentMeterDev
################################################################
sub _setmeterDevice {                    ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $arg   = $paref->{arg};

  if(!$arg) {
      return qq{The command "$opt" needs an argument !};
  }
  
  my ($a,$h) = parseParams ($arg);
  my $medev  = $a->[0] // "";
  
  if(!$medev || !$defs{$medev}) {
      return qq{The device "$medev" doesn't exist!};
  }
  
  if(!$h->{gcon} || !$h->{contotal} || !$h->{gfeedin} || !$h->{feedtotal}) {
      return qq{The syntax of "$opt" is not correct. Please consider the commandref.};
  }

  if($h->{gcon} eq "-gfeedin" && $h->{gfeedin} eq "-gcon") {
      return qq{Incorrect input. It is not allowed that the keys gcon and gfeedin refer to each other.};
  }  

  readingsSingleUpdate($hash, "currentMeterDev", $arg, 1);
  createNotifyDev     ($hash);
  writeDataToFile     ($hash, "plantconfig", $plantcfg.$name);             # Anlagenkonfiguration File schreiben

return;
}

################################################################
#                      Setter currentBatteryDev
################################################################
sub _setbatteryDevice {                  ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $arg   = $paref->{arg};

  if(!$arg) {
      return qq{The command "$opt" needs an argument !};
  }
  
  my ($a,$h) = parseParams ($arg);
  my $badev  = $a->[0] // "";
  
  if(!$badev || !$defs{$badev}) {
      return qq{The device "$badev" doesn't exist!};
  }
  
  if(!$h->{pin} || !$h->{pout}) {
      return qq{The syntax of "$opt" is not correct. Please consider the commandref.};
  }

  if($h->{pin} eq "-pout" && $h->{pout} eq "-pin") {
      return qq{Incorrect input. It is not allowed that the keys pin and pout refer to each other.};
  }  

  readingsSingleUpdate($hash, "currentBatteryDev", $arg, 1);
  createNotifyDev     ($hash);
  writeDataToFile     ($hash, "plantconfig", $plantcfg.$name);             # Anlagenkonfiguration File schreiben

return;
}

################################################################
#                      Setter powerTrigger
################################################################
sub _setpowerTrigger {                    ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $arg   = $paref->{arg};

  if(!$arg) {
      return qq{The command "$opt" needs an argument !};
  }
  
  my ($a,$h) = parseParams ($arg);
  
  if(!$h) {
      return qq{The syntax of "$opt" is not correct. Please consider the commandref.};
  }
  
  for my $key (keys %{$h}) {
      if($key !~ /^[0-9]+(?:on|off)$/x || $h->{$key} !~ /^[0-9]+$/x) {
          return qq{The key "$key" is invalid. Please consider the commandref.};
      }
  }
  
  writeDataToFile     ($hash, "plantconfig", $plantcfg.$name);             # Anlagenkonfiguration File schreiben

  readingsSingleUpdate($hash, "powerTrigger", $arg, 1);

return;
}

################################################################
#                      Setter energyH4Trigger
################################################################
sub _setenergyH4Trigger {                ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $arg   = $paref->{arg};

  if(!$arg) {
      return qq{The command "$opt" needs an argument !};
  }
  
  my ($a,$h) = parseParams ($arg);
  
  if(!$h) {
      return qq{The syntax of "$opt" is not correct. Please consider the commandref.};
  }
  
  for my $key (keys %{$h}) {
      if($key !~ /^[0-9]+(?:on|off)$/x || $h->{$key} !~ /^[0-9]+$/x) {
          return qq{The key "$key" is invalid. Please consider the commandref.};
      }
  }
  
  writeDataToFile     ($hash, "plantconfig", $plantcfg.$name);             # Anlagenkonfiguration File schreiben

  readingsSingleUpdate($hash, "energyH4Trigger", $arg, 1);

return;
}

################################################################
#                      Setter modulePeakString
################################################################
sub _setmodulePeakString {               ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $arg   = $paref->{arg} // return qq{no PV module peak specified};
  
  $arg =~ s/,/./xg;
  
  my ($a,$h) = parseParams ($arg); 
  
  if(!keys %$h) {
      return qq{The provided PV module peak has wrong format};
  }
  
  while (my ($key, $value) = each %$h) {
      if($value !~ /[0-9.]/x) {
          return qq{The module peak of "$key" must be specified by numbers and optionally with decimal places};
      }     
  }
  
  readingsSingleUpdate($hash, "modulePeakString", $arg, 1);
  
  my $ret = createStringConfig ($hash);
  return $ret if($ret);
  
  writeDataToFile ($hash, "plantconfig", $plantcfg.$name);             # Anlagenkonfiguration File schreiben

return;
}

################################################################
#                      Setter moduleTiltAngle
################################################################
sub _setmoduleTiltAngle {                ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $arg   = $paref->{arg} // return qq{no tilt angle was provided};
  
  my $tilt  = join "|", sort keys %hff;

  my ($a,$h) = parseParams ($arg); 
  
  if(!keys %$h) {
      return qq{The provided tilt angle has wrong format};
  }

  while (my ($key, $value) = each %$h) {
      if($value !~ /^(?:$tilt)$/x) {
          return qq{The tilt angle of "$key" is wrong};
      }     
  }
    
  readingsSingleUpdate($hash, "moduleTiltAngle", $arg, 1);
    
  my $ret = createStringConfig ($hash);
  return $ret if($ret);

  writeDataToFile ($hash, "plantconfig", $plantcfg.$name);             # Anlagenkonfiguration File schreiben  

return;
}

################################################################
#                 Setter moduleDirection
################################################################
sub _setmoduleDirection {                ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $arg   = $paref->{arg} // return qq{no module direction was provided};

  my $dirs  = "N|NE|E|SE|S|SW|W|NW";                                          # mögliche Richtungsangaben
  
  my ($a,$h) = parseParams ($arg); 
  
  if(!keys %$h) {
      return qq{The provided module direction has wrong format};
  }
  
  while (my ($key, $value) = each %$h) {
      if($value !~ /^(?:$dirs)$/x) {
          return qq{The module direction of "$key" is wrong: $value};
      }     
  }

  readingsSingleUpdate($hash, "moduleDirection", $arg, 1);
  
  my $ret = createStringConfig ($hash);
  return $ret if($ret);
  
  writeDataToFile ($hash, "plantconfig", $plantcfg.$name);                   # Anlagenkonfiguration File schreiben

return;
}

################################################################
#                      Setter plantConfiguration
################################################################
sub _setplantConfiguration {             ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $arg   = $paref->{arg};

  if(!$arg) {
      return qq{The command "$opt" needs an argument !};
  } 
  
  if($arg eq "check") {      
      my $ret = checkStringConfig ($hash); 
      return qq{<html>$ret</html>};
  }
  
  if($arg eq "save") {
      my $error = writeDataToFile ($hash, "plantconfig", $plantcfg.$name);             # Anlagenkonfiguration File schreiben
      if($error) {
          return $error;
      }
      else {
          return qq{Plant Configuration has been written to file "$plantcfg.$name"};
      }
  }
  
  if($arg eq "restore") {
      my ($error, @pvconf) = FileRead ($plantcfg.$name);                                        
      
      if(!$error) {
          my $rbit = 0;
          for my $elem (@pvconf) {
              my ($reading, $val) = split "<>", $elem;
              next if(!$reading || !defined $val);
              CommandSetReading (undef,"$name $reading $val");
              $rbit = 1;
          }          
          
          if($rbit) {
              return qq{Plant Configuration restored from file "$plantcfg.$name"};
          }
          else {
              return qq{The Plant Configuration file "$plantcfg.$name" was empty, nothing restored};
          }
      }
      else {
          return $error;
      }      
  }
  
return;
}

################################################################
#                      Setter pvCorrectionFactor
################################################################
sub _setpvCorrectionFactor {             ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop} // return qq{no correction value specified};

  if($prop !~ /[0-9,.]/x) {
      return qq{The correction value must be specified by numbers and optionally with decimal places};
  }
  
  $prop =~ s/,/./x;
  
  readingsSingleUpdate($hash, $opt, $prop." (manual)", 1);
  
  my $cfnum = (split "_", $opt)[1]; 
  deleteReadingspec ($hash, "pvCorrectionFactor_${cfnum}_autocalc");
  
  centralTask ($hash);

return;
}

################################################################
#                 Setter pvCorrectionFactor_Auto
################################################################
sub _setpvCorrectionFactorAuto {         ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop} // return qq{no correction value specified};
  
  readingsSingleUpdate($hash, "pvCorrectionFactor_Auto", $prop, 1);
  
  if($prop eq "off") {
      deleteReadingspec ($hash, "pvCorrectionFactor_.*_autocalc");
  }
  
   writeDataToFile ($hash, "plantconfig", $plantcfg.$name);                    # Anlagenkonfiguration sichern

return;
}

################################################################
#                      Setter reset
################################################################
sub _setreset {                          ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop} // return qq{no source specified for reset};
  
  my $type  = $hash->{TYPE};
  
  if($prop eq "pvHistory") {
      my $day   = $paref->{prop1} // "";                                       # ein bestimmter Tag der pvHistory angegeben ?
      my $dhour = $paref->{prop2} // "";                                       # eine bestimmte Stunde eines Tages der pvHistory angegeben ?

      if ($day) {
          if($dhour) {
              delete $data{$type}{$name}{pvhist}{$day}{$dhour};
              Log3($name, 3, qq{$name - Hour "$dhour" of day "$day" deleted in pvHistory});             
          }
          else {
              delete $data{$type}{$name}{pvhist}{$day};
              Log3($name, 3, qq{$name - Day "$day" deleted in pvHistory});
          }
      }
      else {
          delete $data{$type}{$name}{pvhist};
          Log3($name, 3, qq{$name - all days of pvHistory deleted});
      }      
      return;
  }
  
  if($prop eq "pvCorrection") {
      for my $n (1..24) {
          $n = sprintf "%02d", $n;
          deleteReadingspec ($hash, "pvCorrectionFactor_${n}.*");
      }
      
      my $circ  = $paref->{prop1} // 'no';                                   # alle pvKorr-Werte aus Circular-Hash löschen ?
      my $circh = $paref->{prop2} // q{};                                    # pvKorr-Werte einer bestimmten Stunde aus Circular-Hash löschen ?
      
      if ($circ eq "circular") {
          if ($circh) {
              delete $data{$type}{$name}{circular}{$circh}{pvcorrf};
              delete $data{$type}{$name}{circular}{$circh}{quality}; 

              Log3($name, 3, qq{$name - stored PV correction factor of hour "$circh" in pvCircular deleted});
              return;              
          }
          
          for my $hod (keys %{$data{$type}{$name}{circular}}) {
              delete $data{$type}{$name}{circular}{$hod}{pvcorrf};
              delete $data{$type}{$name}{circular}{$hod}{quality};
          }
          
          Log3($name, 3, qq{$name - all stored PV correction factors in pvCircular deleted});
      }
      return;
  }
  
  if($prop eq "powerTrigger") {
      deleteReadingspec ($hash, "powerTrigger.*");
      writeDataToFile   ($hash, "plantconfig", $plantcfg.$name);           # Anlagenkonfiguration File schreiben
      return;
  }
  
  if($prop eq "energyH4Trigger") {
      deleteReadingspec ($hash, "energyH4Trigger.*");
      writeDataToFile   ($hash, "plantconfig", $plantcfg.$name);           # Anlagenkonfiguration File schreiben
      return;
  }

  readingsDelete($hash, $prop);
  
  if($prop eq "currentMeterDev") {
      readingsDelete($hash, "Current_GridConsumption");
      readingsDelete($hash, "Current_GridFeedIn");
      delete $hash->{HELPER}{INITCONTOTAL};
      delete $hash->{HELPER}{INITFEEDTOTAL};
      delete $data{$type}{$name}{current}{gridconsumption};
      delete $data{$type}{$name}{current}{tomorrowconsumption};
      delete $data{$type}{$name}{current}{gridfeedin};
      delete $data{$type}{$name}{current}{consumption};
      delete $data{$type}{$name}{current}{autarkyrate};
      delete $data{$type}{$name}{current}{selfconsumption};
      delete $data{$type}{$name}{current}{selfconsumptionrate};
      
      writeDataToFile ($hash, "plantconfig", $plantcfg.$name);                       # Anlagenkonfiguration File schreiben
  }
  
  if($prop eq "currentBatteryDev") {
      readingsDelete($hash, "Current_PowerBatIn");
      readingsDelete($hash, "Current_PowerBatOut");
      readingsDelete($hash, "Current_BatCharge");
      delete $data{$type}{$name}{current}{powerbatout};
      delete $data{$type}{$name}{current}{powerbatin};
      delete $data{$type}{$name}{current}{batcharge};
      
      writeDataToFile ($hash, "plantconfig", $plantcfg.$name);                       # Anlagenkonfiguration File schreiben
  }
  
  if($prop eq "currentInverterDev") {
      readingsDelete    ($hash, "Current_PV");
      deleteReadingspec ($hash, ".*_PVreal" );
      writeDataToFile   ($hash, "plantconfig", $plantcfg.$name);                     # Anlagenkonfiguration File schreiben
  }
  
  if($prop eq "consumerPlanning") {                                                  # Verbraucherplanung resetten
      my $c = $paref->{prop1} // "";                                                 # bestimmten Verbraucher setzen falls angegeben
      
      if ($c) {
          deleteConsumerPlanning ($hash, $c);
          my $calias = ConsumerVal ($hash, $c, "alias", "");
          Log3($name, 3, qq{$name - Consumer planning of "$calias" deleted});
      }
      else {
          for my $cs (keys %{$data{$type}{$name}{consumers}}) {
              deleteConsumerPlanning ($hash, $cs);
              my $calias = ConsumerVal ($hash, $cs, "alias", "");
              Log3($name, 3, qq{$name - Consumer planning of "$calias" deleted});
          }           
      }
      
      writeDataToFile ($hash, "consumers", $csmcache.$name);                         # Cache File Consumer schreiben
  }

  if($prop eq "consumerMaster") {                                                    # Verbraucherhash löschen
      my $c = $paref->{prop1} // "";                                                 # bestimmten Verbraucher setzen falls angegeben
      
      if ($c) {
          my $calias = ConsumerVal ($hash, $c, "alias", "");
          delete $data{$type}{$name}{consumers}{$c};
          Log3($name, 3, qq{$name - Consumer "$calias" deleted from memory});
      }
      else {
          for my $cs (keys %{$data{$type}{$name}{consumers}}) {
              my $calias = ConsumerVal ($hash, $cs, "alias", "");
              delete $data{$type}{$name}{consumers}{$cs};
              Log3($name, 3, qq{$name - Consumer "$calias" deleted from memory});
          }           
      }
      
      writeDataToFile ($hash, "consumers", $csmcache.$name);                         # Cache File Consumer schreiben
  }   
  
  createNotifyDev ($hash);

return;
}

################################################################
#                      Setter writeHistory
################################################################
sub _setwriteHistory {                   ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  
  my $ret;
  
  $ret = writeDataToFile ($hash, "circular", $pvccache.$name);             # Cache File für PV Circular schreiben
  $ret = writeDataToFile ($hash, "pvhist",   $pvhcache.$name);             # Cache File für PV History schreiben

return $ret;
}

################################################################
#              Setter consumerAction
#      ohne Menüeintrag ! für Aktivität aus Grafik
################################################################
sub _setconsumerAction {                 ## no critic "not used"
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $opt     = $paref->{opt};
  my $arg     = $paref->{arg};
  my $argsref = $paref->{argsref};

  if(!$arg) {
      return qq{The command "$opt" needs an argument !};
  }
  
  my @args = @{$argsref};
  
  my $action = shift @args;                                                 # z.B. set, setreading
  my $cname  = shift @args;                                                 # Consumername
  my $tail   = join " ", map { my $p = $_; $p =~ s/\s//xg; $p; } @args;     ## no critic 'Map blocks' # restliche Befehlsargumente 
  
  if($action eq "set") {
      CommandSet (undef, "$cname $tail");
  }
  
  if($action eq "setreading") {
      CommandSetReading (undef, "$cname $tail");
  }
  
  if($action eq "consumerImmediatePlanning") {
      CommandSet (undef, "$name $action $cname noTaskcall");
  }
  
  Log3($name, 4, qq{$name - Consumer Action received / executed: "$action $cname $tail"});
  
  centralTask ($hash);

return;
}

###############################################################
#                  SolarForecast Get
###############################################################
sub Get {
  my ($hash, @a) = @_;
  return "\"get X\" needs at least an argument" if ( @a < 2 );
  my $name = shift @a;
  my $opt  = shift @a;
  my $arg  = join " ", map { my $p = $_; $p =~ s/\s//xg; $p; } @a;     ## no critic 'Map blocks'
 
  my $getlist = "Unknown argument $opt, choose one of ".
                "valConsumerMaster:noArg ".
                "data:noArg ".
                "forecastQualities:noArg ".
                "html:noArg ".
                "nextHours:noArg ".
                "pvCircular:noArg ".
                "pvHistory:noArg ".
                "valCurrent:noArg "
                ;
                
  return if(IsDisabled($name));
  
  my $params = {
      hash  => $hash,
      name  => $name,
      opt   => $opt,
      arg   => $arg
  };
  
  if($hget{$opt} && defined &{$hget{$opt}{fn}}) {
      my $ret = q{}; 
      if (!$hash->{CREDENTIALS} && $hget{$opt}{needcred}) {                
          return qq{Credentials of $name are not set."};
      }
      $ret = &{$hget{$opt}{fn}} ($params);
      return $ret;
  }
  
return $getlist;
}

###############################################################
#                       Getter data
###############################################################
sub _getdata {
  my $paref = shift;
  my $hash  = $paref->{hash};
  
return centralTask ($hash);
}

###############################################################
#                       Getter html
###############################################################
sub _gethtml {
  my $paref = shift;
  my $hash  = $paref->{hash};
  
return pageAsHtml ($hash);
}

###############################################################
#                       Getter ftui
#                ohne Eintrag in Get-Liste
###############################################################
sub _getftui {
  my $paref = shift;
  my $hash  = $paref->{hash};
  
return pageAsHtml ($hash,"ftui");
}

###############################################################
#                       Getter pvHistory
###############################################################
sub _getlistPVHistory {
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  my $ret   = listDataPool ($hash, "pvhist");
                    
return $ret;
}

###############################################################
#                       Getter pvCircular
###############################################################
sub _getlistPVCircular {
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  my $ret   = listDataPool ($hash, "circular");
                    
return $ret;
}

###############################################################
#                       Getter nextHours
###############################################################
sub _getlistNextHours {
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  my $ret   = listDataPool ($hash, "nexthours");
                    
return $ret;
}

###############################################################
#                       Getter pvQualities
###############################################################
sub _getForecastQualities {
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  my $ret   = listDataPool ($hash, "qualities");
                    
return $ret;
}

###############################################################
#                       Getter valCurrent
###############################################################
sub _getlistCurrent {
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  my $ret   = listDataPool ($hash, "current");
                    
return $ret;
}

###############################################################
#                       Getter valConsumerMaster
###############################################################
sub _getlistvalConsumerMaster {
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  my $ret   = listDataPool ($hash, "consumer");
                    
return $ret;
}

################################################################
sub Attr {
  my $cmd   = shift;
  my $name  = shift;
  my $aName = shift;
  my $aVal  = shift;
  my $hash  = $defs{$name};
    
  my ($do,$val);
      
  # $cmd can be "del" or "set"
  # $name is device name
  # aName and aVal are Attribute name and value
    
  if($aName eq "disable") {
      if($cmd eq "set") {
          $do = ($aVal) ? 1 : 0;
      }
      $do  = 0 if($cmd eq "del");
      $val = ($do == 1 ? "disabled" : "initialized");
      readingsSingleUpdate($hash, "state", $val, 1);
  }
    
  if ($cmd eq "set") {
      if ($aName eq "interval") {
          unless ($aVal =~ /^[0-9]+$/x) {return "The value for $aName is not valid. Use only figures 0-9 !";}
          InternalTimer(gettimeofday()+1.0, "FHEM::SolarForecast::centralTask", $hash, 0);
      }  
        
      if ($aName eq "maxVariancePerDay") {
          unless ($aVal =~ /^[0-9.]+$/x) {return "The value for $aName is not valid. Use only numbers with optional decimal places !";}
      }         
  }
    
  my $params = {
      hash  => $hash,
      name  => $name,
      cmd   => $cmd,
      aName => $aName,
      aVal  => $aVal
  };
  
  $aName = "consumer" if($aName =~ /consumer?(\d+)$/xs);
  
  if($hattr{$aName} && defined &{$hattr{$aName}{fn}}) {
      my $ret = q{};
      $ret    = &{$hattr{$aName}{fn}} ($params); 
      return $ret;
  }

return;
}

################################################################
#                      Attr consumer
################################################################
sub _attrconsumer {                      ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $aName = $paref->{aName};
  my $aVal  = $paref->{aVal};
  my $cmd   = $paref->{cmd};
  
  return if(!$init_done);                                                                  # Forum: https://forum.fhem.de/index.php/topic,117864.msg1159959.html#msg1159959
  
  if($cmd eq "set") {
      my ($a,$h) = parseParams ($aVal);
      my $codev  = $a->[0] // "";
      
      if(!$codev || !$defs{$codev}) {
          return qq{The device "$codev" doesn't exist!};
      }
      
      if(!$h->{type} || !$h->{power}) {
          return qq{The syntax of "$aName" is not correct. Please consider the commandref.};
      }
      
      my $alowt = $h->{type} ~~ @ctypes ? 1 : 0;
      if(!$alowt) {
        return qq{The type "$h->{type}" isn't allowed!};
      }
      
      if($h->{power} !~ /^[0-9]+$/xs) {
          return qq{The key "power" must be specified only by numbers without decimal places};
      }

      if($h->{mode} && $h->{mode} !~ /^(?:can|must)$/xs) {
          return qq{The mode "$h->{mode}" isn't allowed!}
      }
  } 
  else {      
      my $day  = strftime "%d", localtime(time);                                           # aktueller Tag  (range 01 to 31)
      my $type = $hash->{TYPE};
      my ($c)  = $aName =~ /consumer([0-9]+)/xs;
  
      deleteReadingspec ($hash, "consumer${c}.*");
      
      for my $i (1..24) {                                                                  # Consumer aus History löschen
          delete $data{$type}{$name}{pvhist}{$day}{sprintf("%02d",$i)}{"csmt${c}"};
          delete $data{$type}{$name}{pvhist}{$day}{sprintf("%02d",$i)}{"csme${c}"};
      }
      
      delete $data{$type}{$name}{pvhist}{$day}{99}{"csmt${c}"};
      delete $data{$type}{$name}{pvhist}{$day}{99}{"csme${c}"};
      delete $data{$type}{$name}{consumers}{$c};                                           # Consumer Hash Verbraucher löschen
  }  

  writeDataToFile ($hash, "consumers", $csmcache.$name);                                   # Cache File Consumer schreiben
  
  InternalTimer(gettimeofday()+5, "FHEM::SolarForecast::createNotifyDev", $hash, 0);

return;
}

################################################################
#               Attr createConsumptionRecReadings
################################################################
sub _attrcreateConsRecRdgs {             ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $aName = $paref->{aName};
  
  if ($aName eq 'createConsumptionRecReadings') {
      deleteReadingspec ($hash, "consumer.*_ConsumptionRecommended");
  }

return;
}

###################################################################################
#                                 Eventverarbeitung
###################################################################################
sub Notify {
  # Es werden nur die Events von Geräten verarbeitet die im Hash $hash->{NOTIFYDEV} gelistet sind (wenn definiert).
  # Dadurch kann die Menge der Events verringert werden. In sub DbRep_Define angeben. 
  my $myHash   = shift;
  my $dev_hash = shift;
  my $myName   = $myHash->{NAME};                                                         # Name des eigenen Devices
  my $devName  = $dev_hash->{NAME};                                                       # Device welches Events erzeugt hat
  
  return;                                                            # !! ZUR ZEIT NICHT GENUTZT !!
  
  return if(IsDisabled($myName) || !$myHash->{NOTIFYDEV}); 
  
  my $events = deviceEvents($dev_hash, 1);
  return if(!$events);
  
  my $cdref     = CurrentVal ($myHash, "consumerdevs", "");                                # alle registrierten Consumer
  my @consumers = ();
  @consumers    = @{$cdref} if(ref $cdref eq "ARRAY");
  
  return if(!@consumers);
  
  if($devName ~~ @consumers) {
      my $cindex;
      my $type = $myHash->{TYPE};
      for my $c (sort{$a<=>$b} keys %{$data{$type}{$myName}{consumers}}) {
          my $cname = ConsumerVal ($myHash, $c, "name", "");
          if($devName eq $cname) {
              $cindex = $c; 
              last;
          }       
      }
      
      my $autoreading = ConsumerVal ($myHash, $cindex, "autoreading", "");  
      
      for my $event (@{$events}) {
          $event  = "" if(!defined($event));
          my @evl = split(/\s+/x, $event);
                    
          my @parts   = split(/: /x,$event, 2);
          my $reading = shift @parts;

          if ($reading eq "state" || $reading eq $autoreading) {
              Log3 ($myName, 4, qq{$myName - start centralTask by Notify - $devName:$reading});
              RemoveInternalTimer($myHash, "FHEM::SolarForecast::centralTask");
              InternalTimer      (gettimeofday()+0.5, "FHEM::SolarForecast::centralTask", $myHash, 0);
          }          
      }
  }
   
return;
}

###############################################################
#                  DbLog_splitFn
###############################################################
sub DbLogSplit {
  my $event  = shift;
  my $device = shift;
  my ($reading, $value, $unit) = ("","","");

  if($event =~ /\s(k?Wh?|%)$/xs) {
      my @parts = split(/\s/x, $event, 3);
      $reading  = $parts[0];
      $reading  =~ tr/://d;
      $value    = $parts[1];
      $unit     = $parts[2];
      
      # Log3 ($device, 1, qq{$device - Split for DbLog done -> Reading: $reading, Value: $value, Unit: $unit});
  }

return ($reading, $value, $unit);
}

################################################################
#                         Shutdown
################################################################
sub Shutdown {  
  my $hash = shift;

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
  writeDataToFile ($hash, "pvhist",    $pvhcache.$name);             # Cache File für PV History schreiben
  writeDataToFile ($hash, "circular",  $pvccache.$name);             # Cache File für PV Circular schreiben
  writeDataToFile ($hash, "consumers", $csmcache.$name);             # Cache File Consumer schreiben
  
return; 
}

################################################################
# Die Undef-Funktion wird aufgerufen wenn ein Gerät mit delete 
# gelöscht wird oder bei der Abarbeitung des Befehls rereadcfg, 
# der ebenfalls alle Geräte löscht und danach das 
# Konfigurationsfile neu einliest. Entsprechend müssen in der 
# Funktion typische Aufräumarbeiten durchgeführt werden wie das 
# saubere Schließen von Verbindungen oder das Entfernen von 
# internen Timern.
################################################################
sub Undef {
 my $hash = shift;
 my $arg  = shift;
 
 RemoveInternalTimer($hash);
    
return;
}

#################################################################
# Wenn ein Gerät in FHEM gelöscht wird, wird zuerst die Funktion 
# X_Undef aufgerufen um offene Verbindungen zu schließen, 
# anschließend wird die Funktion X_Delete aufgerufen. 
# Funktion: Aufräumen von dauerhaften Daten, welche durch das 
# Modul evtl. für dieses Gerät spezifisch erstellt worden sind. 
# Es geht hier also eher darum, alle Spuren sowohl im laufenden 
# FHEM-Prozess, als auch dauerhafte Daten bspw. im physikalischen 
# Gerät zu löschen die mit dieser Gerätedefinition zu tun haben. 
#################################################################
sub Delete {
  my $hash  = shift;
  my $arg   = shift;
  my $name  = $hash->{NAME};
  
  my $file  = $pvhcache.$name;                                                # Cache File PV History löschen
  my $error = FileDelete($file);      

  if ($error) {
      Log3 ($name, 1, qq{$name - ERROR deleting file "$file": $error}); 
  }
  
  $error = qq{};
  $file  = $pvccache.$name;                                                   # Cache File PV Circular löschen
  $error = FileDelete($file); 
  
  if ($error) {
      Log3 ($name, 1, qq{$name - ERROR deleting file "$file": $error}); 
  }
  

  $error = qq{};
  $file  = $plantcfg.$name;                                                   # File Anlagenkonfiguration löschen
  $error = FileDelete($file); 
  
  if ($error) {
      Log3 ($name, 1, qq{$name - ERROR deleting file "$file": $error}); 
  }
  
  $error = qq{};
  $file  = $csmcache.$name;                                                   # File Consumer löschen
  $error = FileDelete($file); 
  
  if ($error) {
      Log3 ($name, 1, qq{$name - ERROR deleting file "$file": $error}); 
  }
      
return;
}

################################################################
#        Timer für historische Daten schreiben
################################################################
sub periodicWriteCachefiles {
  my $hash = shift;
  my $name = $hash->{NAME};
  
  RemoveInternalTimer($hash, "FHEM::SolarForecast::periodicWriteCachefiles");
  InternalTimer      (gettimeofday()+$whistrepeat, "FHEM::SolarForecast::periodicWriteCachefiles", $hash, 0);
  
  return if(IsDisabled($name));
  
  writeDataToFile ($hash, "circular",  $pvccache.$name);             # Cache File für PV Circular schreiben
  writeDataToFile ($hash, "pvhist",    $pvhcache.$name);             # Cache File für PV History schreiben
  
return;
}

################################################################
#             Daten in File wegschreiben
################################################################
sub writeDataToFile {  
  my $hash      = shift;
  my $cachename = shift;
  my $file      = shift;

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
  my @data;
  
  if($cachename eq "plantconfig") {
      @data = _savePlantConfig ($hash);
      return "Plant configuration is empty, no data has been written" if(!@data);
  }
  else {
      return if(!$data{$type}{$name}{$cachename});
      my $json = encode_json ($data{$type}{$name}{$cachename});
      push @data, $json;
  }
  
  my $error = FileWrite($file, @data);
  
  if ($error) {
      my $err = qq{ERROR writing cache file "$file": $error};
      Log3 ($name, 1, "$name - $err");
      readingsSingleUpdate($hash, "state", "ERROR writing cache file $file - $error", 1);
      return $err;          
  }
  else {
      my $lw = gettimeofday(); 
      $hash->{HISTFILE} = "last write time: ".FmtTime($lw)." File: $file" if($cachename eq "pvhist");
      readingsSingleUpdate($hash, "state", "wrote cachefile $cachename successfully", 1);
  }
   
return; 
}

################################################################
#          Anlagenkonfiguration sichern
################################################################
sub _savePlantConfig {  
  my $hash = shift;
  my $name = $hash->{NAME};
  
  my @pvconf;
  
  my @aconfigs = qw(
                     pvCorrectionFactor_Auto
                     currentBatteryDev
                     currentForecastDev
                     currentInverterDev
                     currentMeterDev
                     currentRadiationDev
                     inverterStrings
                     moduleDirection
                     modulePeakString
                     moduleTiltAngle
                     powerTrigger
                     energyH4Trigger
                   );

  for my $cfg (@aconfigs) {
      my $val = ReadingsVal($name, $cfg, "");
      next if(!$val);
      push @pvconf, $cfg."<>".$val;    
  } 
   
return @pvconf; 
}

################################################################
#                       Zentraler Datenabruf
################################################################
sub centralTask {
  my $hash = shift;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};  
  
  RemoveInternalTimer($hash, "FHEM::SolarForecast::centralTask");
  
  ### nicht mehr benötigte Readings/Daten löschen - kann später wieder raus !!
  #for my $i (keys %{$data{$type}{$name}{pvhist}}) {
  #    delete $data{$type}{$name}{pvhist}{$i}{"00"};
  #    delete $data{$type}{$name}{pvhist}{$i} if(!$i);               # evtl. vorhandene leere Schlüssel entfernen
  #}
  
  #for my $c (keys %{$data{$type}{$name}{consumers}}) {
  #    delete $data{$type}{$name}{consumers}{$c}{OnOff};
  #}
  
  #deleteReadingspec ($hash, "Today_Hour.*_Consumption");
  #deleteReadingspec ($hash, "ThisHour_.*");
  #deleteReadingspec ($hash, "Today_PV");
  #deleteReadingspec ($hash, "Tomorrow_PV");
  #deleteReadingspec ($hash, "Next04Hours_PV");
  #deleteReadingspec ($hash, "Next.*HoursPVforecast");
  #deleteReadingspec ($hash, "moduleEfficiency");
  #deleteReadingspec ($hash, "RestOfDay_PV");
  #deleteReadingspec ($hash, "CurrentHourPVforecast");
  #deleteReadingspec ($hash, "NextHours_Sum00_PVforecast"); 

  my $interval = controlParams ($name); 
  
  if($init_done == 1) {
      if(!$interval) {
          $hash->{MODE} = "Manual";
          readingsSingleUpdate($hash, "nextPolltime", "Manual", 1);
      } 
      else {
          my $new = gettimeofday()+$interval; 
          InternalTimer($new, "FHEM::SolarForecast::centralTask", $hash, 0);                       # Wiederholungsintervall
          $hash->{MODE} = "Automatic - next polltime: ".FmtTime($new);
          readingsSingleUpdate($hash, "nextPolltime", FmtTime($new), 1);
      }
      
      return if(IsDisabled($name));
      
      readingsSingleUpdate($hash, "state", "running", 1);

      my $stch = $data{$type}{$name}{strings};                                                     # String Config Hash
      if (!keys %{$stch}) {
          my $ret = createStringConfig ($hash);                                                    # die String Konfiguration erstellen
          if ($ret) {
              readingsSingleUpdate($hash, "state", $ret, 1);
              return;
          }
      }      
      
      my @da;
      my $t       = time;                                                                          # aktuelle Unix-Zeit 
      my $date    = strftime "%Y-%m-%d", localtime($t);                                            # aktuelles Datum
      my $chour   = strftime "%H", localtime($t);                                                  # aktuelle Stunde 
      my $minute  = strftime "%M", localtime($t);                                                  # aktuelle Minute
      my $day     = strftime "%d", localtime($t);                                                  # aktueller Tag  (range 01 to 31)
      my $dayname = strftime "%a", localtime($t);                                                  # aktueller Wochentagsname

      my $centpars = {
          hash    => $hash,
          name    => $name,
          t       => $t,
          date    => $date,
          minute  => $minute,
          chour   => $chour,
          day     => $day,
          dayname => $dayname,
          state   => "updated",
          daref   => \@da
      };
      
      Log3 ($name, 4, "$name - ################################################################");
      Log3 ($name, 4, "$name - ###                New data collection cycle                 ###");
      Log3 ($name, 4, "$name - ################################################################");
      Log3 ($name, 4, "$name - current hour of day: ".($chour+1));
      
      collectAllRegConsumers     ($centpars);                                                        # alle Verbraucher Infos laden
      
      _specialActivities         ($centpars);                                                        # zusätzliche Events generieren + Sonderaufgaben
      _transferWeatherValues     ($centpars);                                                        # Wetterwerte übertragen
      _transferDWDForecastValues ($centpars);                                                        # Forecast Werte übertragen  
      _transferInverterValues    ($centpars);                                                        # WR Werte übertragen
      _transferMeterValues       ($centpars);                                                        # Energy Meter auswerten    
      _transferBatteryValues     ($centpars);                                                        # Batteriewerte einsammeln
      _manageConsumerData        ($centpars);                                                        # Consumerdaten sammeln und planen  
      _estConsumptionForecast    ($centpars);                                                        # erwarteten Verbrauch berechnen
      _evaluateThresholds        ($centpars);                                                        # Schwellenwerte bewerten und signalisieren  
      _calcReadingsTomorrowPVFc  ($centpars);                                                        # zusätzliche Readings Tomorrow_HourXX_PVforecast berechnen
      _calcSummaries             ($centpars);                                                        # Zusammenfassungen erstellen

      if(@da) {
          createReadingsFromArray ($hash, \@da, 1);
      }
      
      calcVariance           ($centpars);                                                            # Autokorrektur berechnen
      saveEnergyConsumption  ($centpars);                                                            # Energie Hausverbrauch speichern
      
      readingsSingleUpdate($hash, "state", $centpars->{state}, 1);                                   # Abschluß state      
  }
  else {
      InternalTimer(gettimeofday()+5, "FHEM::SolarForecast::centralTask", $hash, 0);
  }
  
return;
}

################################################################
#       Erstellen der Stringkonfiguration
#       Stringhash: $data{$type}{$name}{strings}
################################################################
sub createStringConfig {                 ## no critic "not used"
  my $hash = shift;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
  delete $data{$type}{$name}{strings};                                                            # Stringhash zurücksetzen
  
  my @istrings = split ",", ReadingsVal ($name, "inverterStrings", "");                           # Stringbezeichner
  
  if(!@istrings) {
      return qq{Define all used strings with command "set $name inverterStrings" first.};
  }
  
  my $tilt     = ReadingsVal ($name, "moduleTiltAngle", "");                                      # Modul Neigungswinkel für jeden Stringbezeichner
  my ($at,$ht) = parseParams ($tilt);
 
  while (my ($key, $value) = each %$ht) {
      if ($key ~~ @istrings) {
          $data{$type}{$name}{strings}{"$key"}{tilt} = $value;
      }
      else {
          return qq{Check "moduleTiltAngle" -> the stringname "$key" is not defined as valid string in reading "inverterStrings"};
      }
  }
  
  my $peak     = ReadingsVal ($name, "modulePeakString", "");                                    # kWp für jeden Stringbezeichner
  my ($aa,$ha) = parseParams ($peak);
 
  while (my ($key, $value) = each %$ha) {
      if ($key ~~ @istrings) {
          $data{$type}{$name}{strings}{"$key"}{peak} = $value;
      }
      else {
          return qq{Check "modulePeakString" -> the stringname "$key" is not defined as valid string in reading "inverterStrings"};
      }
  }
  
  my $dir      = ReadingsVal ($name, "moduleDirection", "");                                    # Modul Ausrichtung für jeden Stringbezeichner
  my ($ad,$hd) = parseParams ($dir);
 
  while (my ($key, $value) = each %$hd) {
      if ($key ~~ @istrings) {
          $data{$type}{$name}{strings}{"$key"}{dir} = $value;
      }
      else {
          return qq{Check "moduleDirection" -> the stringname "$key" is not defined as valid string in reading "inverterStrings"};
      }
  }  
  
  if(!keys %{$data{$type}{$name}{strings}}) {
      return qq{The string configuration is empty.\nPlease check the settings of inverterStrings, modulePeakString, moduleDirection, moduleTiltAngle};
  }
  
  my @sca = keys %{$data{$type}{$name}{strings}};                                               # Gegencheck ob nicht mehr Strings in inverterStrings enthalten sind als eigentlich verwendet
  my @tom;
  for my $sn (@istrings) {
      next if ($sn ~~ @sca);
      push @tom, $sn;      
  }
  if(@tom) {
      return qq{Some Strings are not used. Please delete this string names from "inverterStrings" :}.join ",",@tom;
  }
   
return;
}

################################################################
#             Steuerparameter berechnen / festlegen
################################################################
sub controlParams {
  my $name = shift;

  my $interval = AttrVal($name, "interval", $definterval);           # 0 wenn manuell gesteuert

return $interval;
}

################################################################
#     Zusätzliche Readings/ Events für Logging generieren und
#     Sonderaufgaben !
################################################################
sub _specialActivities {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $date  = $paref->{date};                                              # aktuelles Datum
  my $chour = $paref->{chour};
  my $daref = $paref->{daref};
  my $t     = $paref->{t};                                                 # aktuelle Zeit
  my $day   = $paref->{day};
  
  my $type  = $hash->{TYPE};
  
  my ($ts,$ts1,$pvfc,$pvrl,$gcon);
  
  $ts1  = $date." ".sprintf("%02d",$chour).":00:00";
  
  $pvfc = ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour)."_PVforecast", 0); 
  push @$daref, "LastHourPVforecast<>".$pvfc." Wh<>".$ts1;
  
  $pvrl = ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour)."_PVreal", 0);
  push @$daref, "LastHourPVreal<>".$pvrl." Wh<>".$ts1;
  
  $gcon = ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour)."_GridConsumption", 0);
  push @$daref, "LastHourGridconsumptionReal<>".$gcon." Wh<>".$ts1; 
  
  ## zusätzliche Events erzeugen - PV Vorhersage bis Ende des kommenden Tages
  #############################################################################
  for my $idx (sort keys %{$data{$type}{$name}{nexthours}}) {                                 
      my $nhts = NexthoursVal ($hash, $idx, "starttime",  undef);
      my $nhfc = NexthoursVal ($hash, $idx, "pvforecast", undef);
      next if(!defined $nhts || !defined $nhfc);
      
      my ($dt, $h) = $nhts =~ /([\w-]+)\s(\d{2})/xs;
      push @$daref, "AllPVforecastsToEvent<>".$nhfc." Wh<>".$dt." ".$h.":59:59";
  }

  ## bestimmte einmalige Aktionen
  ##################################  
  my $tlim = "00";                                                                                              
  if($chour =~ /^($tlim)$/x) {
      if(!exists $hash->{HELPER}{H00DONE}) {
          $date = strftime "%Y-%m-%d", localtime($t-7200);                                    # Vortag (2 h Differenz reichen aus)
          $ts   = $date." 23:59:59";
          
          $pvfc = ReadingsNum($name, "Today_Hour24_PVforecast", 0);  
          push @$daref, "LastHourPVforecast<>".$pvfc."<>".$ts;
          
          $pvrl = ReadingsNum($name, "Today_Hour24_PVreal", 0);
          push @$daref, "LastHourPVreal<>".$pvrl."<>".$ts;
          
          $gcon = ReadingsNum($name, "Today_Hour24_GridConsumption", 0);
          push @$daref, "LastHourGridconsumptionReal<>".$gcon."<>".$ts;

          writeDataToFile ($hash, "plantconfig", $plantcfg.$name);                           # Anlagenkonfiguration sichern          
          
          deleteReadingspec ($hash, "Today_Hour.*_Grid.*");
          deleteReadingspec ($hash, "Today_Hour.*_PV.*");
          deleteReadingspec ($hash, "Today_Hour.*_Bat.*");
          deleteReadingspec ($hash, "powerTrigger_.*");
          
          if(ReadingsVal ($name, "pvCorrectionFactor_Auto", "off") eq "on") {
              for my $n (1..24) {
                  $n = sprintf "%02d", $n;
                  deleteReadingspec ($hash, "pvCorrectionFactor_${n}.*");
              }
          }
                  
          delete $hash->{HELPER}{INITCONTOTAL};
          delete $hash->{HELPER}{INITFEEDTOTAL};
          
          delete $data{$type}{$name}{pvhist}{$day};                                         # den (alten) aktuellen Tag löschen
          Log3 ($name, 3, qq{$name - history day "$day" deleted});
          
          for my $c (keys %{$data{$type}{$name}{consumers}}) {
              deleteConsumerPlanning ($hash, $c);
              my $calias = ConsumerVal ($hash, $c, "alias", "");
              Log3 ($name, 3, qq{$name - Consumer planning of "$calias" deleted});
              
              $data{$type}{$name}{consumers}{$c}{minutesOn}       = 0;
              $data{$type}{$name}{consumers}{$c}{numberDayStarts} = 0;
              $data{$type}{$name}{consumers}{$c}{onoff}           = "off";
          }
          
          deleteReadingspec ($hash, "consumer.*_planned.*"); 

          writeDataToFile ($hash, "consumers", $csmcache.$name);                            # Cache File Consumer schreiben          
          
          $hash->{HELPER}{H00DONE} = 1;
      }
  }
  else {
      delete $hash->{HELPER}{H00DONE};
  }  
  
return;
}

################################################################
#    Forecast Werte Device (DWD_OpenData) ermitteln und 
#    übertragen
################################################################
sub _transferDWDForecastValues {               
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $t     = $paref->{t};                                                                     # Epoche Zeit
  my $chour = $paref->{chour};
  my $daref = $paref->{daref};
  
  my $raname = ReadingsVal($name, "currentRadiationDev", "");                                  # Radiation Forecast Device
  return if(!$raname || !$defs{$raname});
  
  my ($time_str,$epoche);
  my $type = $hash->{TYPE};
  my $uac  = ReadingsVal($name, "pvCorrectionFactor_Auto", "off");                             # Auto- oder manuelle Korrektur
    
  my $err         = checkdwdattr ($name,$raname,\@draattrmust);
  $paref->{state} = $err if($err);
  
  for my $num (0..47) {      
      my ($fd,$fh) = _calcDayHourMove ($chour, $num);
      
      if($fd > 1) {                                                                           # überhängende Werte löschen 
          delete $data{$type}{$name}{nexthours}{"NextHour".sprintf("%02d",$num)};
          next;
      }
      
      my $fh1 = $fh+1;
      my $fh2 = $fh1 == 24 ? 23 : $fh1;
      my $rad = ReadingsVal($raname, "fc${fd}_${fh2}_Rad1h", 0);
      
      Log3 ($name, 5, "$name - collect Radiation data: device=$raname, rad=fc${fd}_${fh2}_Rad1h, Rad1h=$rad");
      
      my $params = {
          hash => $hash,
          name => $name,
          rad  => $rad,
          t    => $t,
          num  => $num,
          uac  => $uac,
          fh   => $fh,
          fd   => $fd,
          day  => $paref->{day}
      };
      
      my $calcpv              = calcPVforecast ($params);                                     # Vorhersage gewichtet kalkulieren
                                       
      $time_str               = "NextHour".sprintf "%02d", $num;
      $epoche                 = $t + (3600*$num);                                                      
      my ($ta,$tsdef,$realts) = timestampToTimestring ($epoche);
      my ($hod)               = $tsdef =~ /\s(\d{2}):/xs;                                     # Stunde des Tages
      $hod                    = sprintf "%02d", int ($hod)+1;
      
      $data{$type}{$name}{nexthours}{$time_str}{pvforecast} = $calcpv;
      $data{$type}{$name}{nexthours}{$time_str}{starttime}  = $tsdef;
      $data{$type}{$name}{nexthours}{$time_str}{hourofday}  = $hod;
      $data{$type}{$name}{nexthours}{$time_str}{today}      = $fd == 0 ? 1 : 0;
      $data{$type}{$name}{nexthours}{$time_str}{Rad1h}      = $rad;                           # nur Info: original Vorhersage Strahlungsdaten
      
      if($num < 23 && $fh < 24) {                                                             # Ringspeicher PV forecast Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350          
          $data{$type}{$name}{circular}{sprintf("%02d",$fh1)}{pvfc} = $calcpv;
      } 
            
      if($fd == 0 && int $calcpv > 0) {                                                       # Vorhersagedaten des aktuellen Tages zum manuellen Vergleich in Reading speichern
          push @$daref, "Today_Hour".sprintf("%02d",$fh1)."_PVforecast<>$calcpv Wh";             
      }
      
      if($fd == 0 && $fh1) {
          $paref->{calcpv}   = $calcpv;
          $paref->{histname} = "pvfc";
          $paref->{nhour}    = sprintf("%02d",$fh1);
          setPVhistory ($paref); 
          delete $paref->{histname};
      }
  }
  
  push @$daref, ".lastupdateForecastValues<>".$t;                                             # Statusreading letzter DWD update
      
return;
}

################################################################
#    Wetter Werte aus dem angebenen Wetterdevice extrahieren
################################################################
sub _transferWeatherValues {               
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $t     = $paref->{t};                                                                      # Epoche Zeit
  my $chour = $paref->{chour};
  my $daref = $paref->{daref};
  
  my $fcname = ReadingsVal($name, "currentForecastDev", "");                                    # Weather Forecast Device
  return if(!$fcname || !$defs{$fcname});
  
  my $err         = checkdwdattr ($name,$fcname,\@dweattrmust);
  $paref->{state} = $err if($err);
  
  my $type = $hash->{TYPE};
  my ($time_str);
  
  my $fc0_SunRise = ReadingsVal($fcname, "fc0_SunRise", "00:00");                               # Sonnenaufgang heute    
  my $fc0_SunSet  = ReadingsVal($fcname, "fc0_SunSet",  "00:00");                               # Sonnenuntergang heute  
  my $fc1_SunRise = ReadingsVal($fcname, "fc1_SunRise", "00:00");                               # Sonnenaufgang morgen   
  my $fc1_SunSet  = ReadingsVal($fcname, "fc1_SunSet",  "00:00");                               # Sonnenuntergang morgen 
  
  push @$daref, "Today_SunRise<>".   $fc0_SunRise;
  push @$daref, "Today_SunSet<>".    $fc0_SunSet;
  push @$daref, "Tomorrow_SunRise<>".$fc1_SunRise;
  push @$daref, "Tomorrow_SunSet<>". $fc1_SunSet;
  
  my $fc0_SunRise_round = sprintf "%02d", (split ":", $fc0_SunRise)[0];
  my $fc0_SunSet_round  = sprintf "%02d", (split ":", $fc0_SunSet)[0];
  my $fc1_SunRise_round = sprintf "%02d", (split ":", $fc1_SunRise)[0];
  my $fc1_SunSet_round  = sprintf "%02d", (split ":", $fc1_SunSet)[0];
  
  for my $num (0..46) {                      
      my ($fd,$fh) = _calcDayHourMove ($chour, $num);
      last if($fd > 1);

      my $fh1   = $fh+1;
      my $fh2   = $fh1 == 24 ? 23 : $fh1;
      my $wid   = ReadingsNum($fcname, "fc${fd}_${fh2}_ww",  -1);
      my $neff  = ReadingsNum($fcname, "fc${fd}_${fh2}_Neff", 0);                              # Effektive Wolkendecke
      my $r101  = ReadingsNum($fcname, "fc${fd}_${fh2}_R101", 0);                              # Niederschlagswahrscheinlichkeit> 0,1 mm während der letzten Stunde
      my $temp  = ReadingsNum($fcname, "fc${fd}_${fh2}_TTT",  0);                              # Außentemperatur
      
      my $fhstr = sprintf "%02d", $fh;                                                         # hier kann Tag/Nacht-Grenze verstellt werden
      
      if($fd == 0 && ($fhstr lt $fc0_SunRise_round || $fhstr gt $fc0_SunSet_round)) {          # Zeit vor Sonnenaufgang oder nach Sonnenuntergang heute
          $wid += 100;                                                                         # "1" der WeatherID voranstellen wenn Nacht
      }
      elsif ($fd == 1 && ($fhstr lt $fc1_SunRise_round || $fhstr gt $fc1_SunSet_round)) {      # Zeit vor Sonnenaufgang oder nach Sonnenuntergang morgen
          $wid += 100;                                                                         # "1" der WeatherID voranstellen wenn Nacht
      }
      
      my $txt = ReadingsVal($fcname, "fc${fd}_${fh2}_wwd", '');

      Log3 ($name, 5, "$name - collect Weather data: device=$fcname, wid=fc${fd}_${fh1}_ww, val=$wid, txt=$txt, cc=$neff, rp=$r101, t=$temp");
      
      $time_str                                             = "NextHour".sprintf "%02d", $num;         
      $data{$type}{$name}{nexthours}{$time_str}{weatherid}  = $wid;
      $data{$type}{$name}{nexthours}{$time_str}{cloudcover} = $neff;
      $data{$type}{$name}{nexthours}{$time_str}{rainprob}   = $r101;
      $data{$type}{$name}{nexthours}{$time_str}{temp}       = $temp;
      
      if($num < 23 && $fh < 24) {                                                              # Ringspeicher Weather Forum: https://forum.fhem.de/index.php/topic,117864.msg1139251.html#msg1139251        
          $data{$type}{$name}{circular}{sprintf("%02d",$fh1)}{weatherid}  = $wid;
          $data{$type}{$name}{circular}{sprintf("%02d",$fh1)}{weathertxt} = $txt;
          $data{$type}{$name}{circular}{sprintf("%02d",$fh1)}{wcc}        = $neff;
          $data{$type}{$name}{circular}{sprintf("%02d",$fh1)}{wrp}        = $r101;
          $data{$type}{$name}{circular}{sprintf("%02d",$fh1)}{temp}       = $temp;
          
          if($num == 0) {                                                                      # aktuelle Außentemperatur
              $data{$type}{$name}{current}{temp} = $temp;   
          }          
      }
      
      if($fd == 0 && $fh1) {                                                                   # Weather in pvhistory speichern
          $paref->{wid}      = $wid;
          $paref->{histname} = "weatherid";
          $paref->{nhour}    = sprintf("%02d",$fh1);
          setPVhistory ($paref); 
          
          $paref->{wcc}      = $neff;
          $paref->{histname} = "weathercloudcover";
          setPVhistory ($paref);
          
          $paref->{wrp}      = $r101;
          $paref->{histname} = "weatherrainprob";
          setPVhistory ($paref);
          
          $paref->{temp}     = $temp;
          $paref->{histname} = "temperature";
          setPVhistory ($paref);
          
          delete $paref->{histname};
      }
  }
      
return;
}

################################################################
#    Werte Inverter Device ermitteln und übertragen
################################################################
sub _transferInverterValues {               
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $t     = $paref->{t};                                                                    # aktuelle Unix-Zeit
  my $chour = $paref->{chour};
  my $day   = $paref->{day};
  my $daref = $paref->{daref};  

  my $indev  = ReadingsVal($name, "currentInverterDev", "");
  my ($a,$h) = parseParams ($indev);
  $indev     = $a->[0] // "";
  return if(!$indev || !$defs{$indev});
             
  my $type = $hash->{TYPE};
  
  my ($pvread,$pvunit) = split ":", $h->{pv};                                                 # Readingname/Unit für aktuelle PV Erzeugung
  my ($edread,$etunit) = split ":", $h->{etotal};                                             # Readingname/Unit für Energie total (PV Erzeugung)
                                                      
  $data{$type}{$name}{current}{invertercapacity} = $h->{capacity} if($h->{capacity});         # optionale Angabe max. WR-Leistung
  
  return if(!$pvread || !$edread);
  
  Log3 ($name, 5, "$name - collect Inverter data: device=$indev, pv=$pvread ($pvunit), etotal=$edread ($etunit)");
  
  my $pvuf = $pvunit =~ /^kW$/xi ? 1000 : 1;
  my $pv   = ReadingsNum ($indev, $pvread, 0) * $pvuf;                                        # aktuelle Erzeugung (W)  
  $pv      = $pv < 0 ? 0 : sprintf("%.0f", $pv);                                              # Forum: https://forum.fhem.de/index.php/topic,117864.msg1159718.html#msg1159718, https://forum.fhem.de/index.php/topic,117864.msg1166201.html#msg1166201
  
  push @$daref, "Current_PV<>". $pv." W";                                          
  $data{$type}{$name}{current}{generation} = $pv;                                             # Hilfshash Wert current generation Forum: https://forum.fhem.de/index.php/topic,117864.msg1139251.html#msg1139251
  
  push @{$data{$type}{$name}{current}{genslidereg}}, $pv;                                     # Schieberegister PV Erzeugung
  limitArray ($data{$type}{$name}{current}{genslidereg}, $defslidenum);
  
  my $etuf   = $etunit =~ /^kWh$/xi ? 1000 : 1;
  my $etotal = ReadingsNum ($indev, $edread, 0) * $etuf;                                      # Erzeugung total (Wh) 
  
  my $nhour  = $chour+1;
  
  my $histetot = HistoryVal ($hash, $day, sprintf("%02d",$nhour), "etotal", 0);               # etotal zu Beginn einer Stunde
  
  my $ethishour;
  if(!$histetot) {                                                                            # etotal der aktuelle Stunde gesetzt ?                                          
      $paref->{etotal}   = $etotal;
      $paref->{nhour}    = sprintf("%02d",$nhour);
      $paref->{histname} = "etotal";
      setPVhistory ($paref);
      delete $paref->{histname};
      
      my $etot   = CurrentVal ($hash, "etotal", $etotal);
      $ethishour = int ($etotal - $etot);
  }
  else {
      $ethishour = int ($etotal - $histetot);
  }
  
  $data{$type}{$name}{current}{etotal} = $etotal;                                             # aktuellen etotal des WR speichern
  
  if($ethishour < 0) {
      $ethishour = 0;
  }
  
  push @$daref, "Today_Hour".sprintf("%02d",$nhour)."_PVreal<>".$ethishour." Wh";       
  $data{$type}{$name}{circular}{sprintf("%02d",$nhour)}{pvrl} = $ethishour;                   # Ringspeicher PV real Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350
  
  $paref->{ethishour} = $ethishour;
  $paref->{nhour}     = sprintf("%02d",$nhour);
  $paref->{histname}  = "pvrl";
  setPVhistory ($paref);
  delete $paref->{histname};

return;
}

################################################################
#    Werte Meter Device ermitteln und übertragen
################################################################
sub _transferMeterValues {               
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $t     = $paref->{t};
  my $chour = $paref->{chour};
  my $daref = $paref->{daref};  

  my $medev  = ReadingsVal($name, "currentMeterDev", "");                                     # aktuelles Meter device
  my ($a,$h) = parseParams ($medev);
  $medev     = $a->[0] // "";
  return if(!$medev || !$defs{$medev});
  
  my $type = $hash->{TYPE}; 
  
  my ($gc,$gcunit) = split ":", $h->{gcon};                                                   # Readingname/Unit für aktuellen Netzbezug
  my ($gf,$gfunit) = split ":", $h->{gfeedin};                                                # Readingname/Unit für aktuelle Netzeinspeisung
  my ($gt,$ctunit) = split ":", $h->{contotal};                                               # Readingname/Unit für Bezug total
  my ($ft,$ftunit) = split ":", $h->{feedtotal};                                              # Readingname/Unit für Einspeisung total
  
  return if(!$gc || !$gf || !$gt || !$ft);
  
  $gfunit //= $gcunit;
  $gcunit //= $gfunit;
  
  Log3 ($name, 5, "$name - collect Meter data: device=$medev, gcon=$gc ($gcunit), gfeedin=$gf ($gfunit) ,contotal=$gt ($ctunit), feedtotal=$ft ($ftunit)");
  
  my ($gco,$gfin);
  
  my $gcuf = $gcunit =~ /^kW$/xi ? 1000 : 1;
  my $gfuf = $gfunit =~ /^kW$/xi ? 1000 : 1;
  
  $gco  = ReadingsNum ($medev, $gc, 0) * $gcuf;                                               # aktueller Bezug (W)
  $gfin = ReadingsNum ($medev, $gf, 0) * $gfuf;                                               # aktuelle Einspeisung (W)
    
  my $params;
  
  if ($gc eq "-gfeedin") {                                                                    # Spezialfall gcon bei neg. gfeedin                                                                                      # Spezialfall: bei negativen gfeedin -> $gco = abs($gf), $gf = 0
      $params = {
          dev  => $medev,
          rdg  => $gf,
          rdgf => $gfuf
      };     
      
      ($gfin,$gco) = substSpecialCases ($params);
  }
  
  if ($gf eq "-gcon") {                                                                       # Spezialfall gfeedin bei neg. gcon
      $params = {
          dev  => $medev,
          rdg  => $gc,
          rdgf => $gcuf
      };      
      
      ($gco,$gfin) = substSpecialCases ($params);
  }
  
  push @$daref, "Current_GridConsumption<>".(int $gco)." W";
  $data{$type}{$name}{current}{gridconsumption} = int $gco;                                   # Hilfshash Wert current grid consumption Forum: https://forum.fhem.de/index.php/topic,117864.msg1139251.html#msg1139251  
  
  push @$daref, "Current_GridFeedIn<>".(int $gfin)." W";
  $data{$type}{$name}{current}{gridfeedin} = int $gfin;                                       # Hilfshash Wert current grid Feed in
  
  my $ctuf    = $ctunit =~ /^kWh$/xi ? 1000 : 1;
  my $gctotal = ReadingsNum ($medev, $gt, 0) * $ctuf;                                         # Bezug total (Wh)    

  my $ftuf    = $ftunit =~ /^kWh$/xi ? 1000 : 1;
  my $fitotal = ReadingsNum ($medev, $ft, 0) * $ftuf;                                         # Einspeisung total (Wh)   
   
  my $gcdaypast = 0;
  my $gfdaypast = 0;
  
  for my $hour (0..int $chour) {                                                                     # alle bisherigen Erzeugungen des Tages summieren                                            
      $gcdaypast += ReadingsNum ($name, "Today_Hour".sprintf("%02d",$hour)."_GridConsumption", 0);
      $gfdaypast += ReadingsNum ($name, "Today_Hour".sprintf("%02d",$hour)."_GridFeedIn",      0);
  }
  
  my $docon = 0;
  if ($gcdaypast == 0) {                                                                             # Management der Stundenberechnung auf Basis Totalwerte GridConsumtion
      if (defined $hash->{HELPER}{INITCONTOTAL}) {
          $docon = 1;
      }
      else {
          $hash->{HELPER}{INITCONTOTAL} = $gctotal;
      }
  }
  elsif (!defined $hash->{HELPER}{INITCONTOTAL}) {
      $hash->{HELPER}{INITCONTOTAL} = $gctotal-$gcdaypast-ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour+1)."_GridConsumption", 0);
  }
  else {
      $docon = 1;
  }
  
  if ($docon) {
      my $gctotthishour = int ($gctotal - ($gcdaypast + $hash->{HELPER}{INITCONTOTAL}));
      
      if($gctotthishour < 0) {
          $gctotthishour = 0;
      }
      
      my $nhour = $chour+1;
      push @$daref, "Today_Hour".sprintf("%02d",$nhour)."_GridConsumption<>".$gctotthishour." Wh";
      $data{$type}{$name}{circular}{sprintf("%02d",$nhour)}{gcons} = $gctotthishour;                  # Hilfshash Wert Bezug (Wh) Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350
      
      $paref->{gctotthishour} = $gctotthishour;
      $paref->{nhour}         = sprintf("%02d",$nhour);
      $paref->{histname}      = "cons";
      setPVhistory ($paref);
      delete $paref->{histname};
  }   
  
  my $dofeed = 0;
  if ($gfdaypast == 0) {                                                                              # Management der Stundenberechnung auf Basis Totalwerte GridFeedIn
      if (defined $hash->{HELPER}{INITFEEDTOTAL}) {
          $dofeed = 1;
      }
      else {
          $hash->{HELPER}{INITFEEDTOTAL} = $fitotal;
      }
  }
  elsif (!defined $hash->{HELPER}{INITFEEDTOTAL}) {
      $hash->{HELPER}{INITFEEDTOTAL} = $fitotal-$gfdaypast-ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour+1)."_GridFeedIn", 0);
  }
  else {
      $dofeed = 1;
  }
  
  if ($dofeed) {
      my $gftotthishour = int ($fitotal - ($gfdaypast + $hash->{HELPER}{INITFEEDTOTAL}));
           
      if($gftotthishour < 0) {
          $gftotthishour = 0;
      }
      
      my $nhour = $chour+1;
      push @$daref, "Today_Hour".sprintf("%02d",$nhour)."_GridFeedIn<>".$gftotthishour." Wh";
      $data{$type}{$name}{circular}{sprintf("%02d",$nhour)}{gfeedin} = $gftotthishour;
      
      $paref->{gftotthishour} = $gftotthishour;
      $paref->{nhour}         = sprintf("%02d",$nhour);
      $paref->{histname}      = "gfeedin";
      setPVhistory ($paref);
      delete $paref->{histname};
  }
      
return;
}

################################################################
#     Consumer - Energieverbrauch aufnehmen 
#              - Masterdata ergänzen
#              - Schaltzeiten planen
################################################################
sub _manageConsumerData {
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $t       = $paref->{t};                                                 # aktuelle Zeit
  my $date    = $paref->{date};                                              # aktuelles Datum
  my $chour   = $paref->{chour};
  my $day     = $paref->{day};
  my $daref   = $paref->{daref};  
    
  my $type    = $hash->{TYPE};   

  my $nhour       = $chour+1;
  $paref->{nhour} = sprintf("%02d",$nhour); 

  for my $c (sort{$a<=>$b} keys %{$data{$type}{$name}{consumers}}) {
      my $consumer = ConsumerVal ($hash, $c, "name",  "");         
      my $alias    = ConsumerVal ($hash, $c, "alias", "");        
      
      ## aktuelle Leistung auslesen 
      ##############################
      my $paread = ConsumerVal ($hash, $c, "rpcurr", "");   
      my $up     = ConsumerVal ($hash, $c, "upcurr", "");   
      my $pcurr  = 0;
      
      if($paread) {
          my $eup = $up =~ /^kW$/xi ? 1000 : 1;
          $pcurr  = ReadingsNum ($consumer, $paread, 0) * $eup; 
          
          push @$daref, "consumer${c}_currentPower<>". $pcurr." W";  
      }

      ## Verbrauch auslesen + speichern
      ##################################
      my $ethreshold = 0;
      my $etotread   = ConsumerVal ($hash, $c, "retotal", ""); 
      my $u          = ConsumerVal ($hash, $c, "uetotal", ""); 
      
      if($etotread) {
          my $eu      = $u =~ /^kWh$/xi ? 1000 : 1;
          my $etot    = ReadingsNum ($consumer, $etotread, 0) * $eu;                               # Summe Energieverbrauch des Verbrauchers
          my $ehist   = HistoryVal  ($hash, $day, sprintf("%02d",$nhour), "csmt${c}", undef);      # gespeicherter Totalverbrauch
          $ethreshold = ConsumerVal ($hash, $c, "energythreshold", 0);                             # Schwellenwert (Wh pro Stunde) ab der ein Verbraucher als aktiv gewertet wird               
          
          ## aktuelle Leitung ermitteln wenn kein Reading d. aktuellen Leistung verfügbar
          ################################################################################
          if(!$paread){
              my $timespan = $t    - ConsumerVal ($hash, $c, "old_etottime",  $t);
              my $delta    = $etot - ConsumerVal ($hash, $c, "old_etotal", $etot);
              $pcurr       = sprintf("%.6f", $delta / (3600 * $timespan)) if($delta);              # Einheitenformel beachten !!: W = Wh / (3600 * s)
            
              $data{$type}{$name}{consumers}{$c}{old_etotal}   = $etot;
              $data{$type}{$name}{consumers}{$c}{old_etottime} = $t;
            
              push @$daref, "consumer${c}_currentPower<>". $pcurr." W";
          }
          
          if(defined $ehist && $etot >= $ehist && ($etot - $ehist) >= $ethreshold) {
              my $consumerco  = $etot - $ehist;
              $consumerco    += HistoryVal ($hash, $day, sprintf("%02d",$nhour), "csme${c}", 0);
 
              $paref->{consumerco} = $consumerco;                                                 # Verbrauch des Consumers aktuelle Stunde
              $paref->{histname}   = "csme${c}";
              setPVhistory ($paref);
              delete $paref->{histname};   
          }   

          $paref->{consumerco} = $etot;                                                           # Totalverbrauch des Verbrauchers
          $paref->{histname}   = "csmt${c}";
          setPVhistory ($paref);
          delete $paref->{histname};
      }
      
      deleteReadingspec ($hash, "consumer${c}_currentPower") if(!$etotread && !$paread);
      
      ## Verbraucher - Laufzeit und Zyklen pro Tag ermitteln
      ## Laufzeit (in Minuten) wird pro Stunde erfasst
      ## bei Tageswechsel Rücksetzen in _specialActivities
      #######################################################
      my $nompower = ConsumerVal ($hash, $c, "power",   0);                                    # nominale Leistung lt. Typenschild
      my $rpcurr   = ConsumerVal ($hash, $c, "rpcurr", "");                                    # Reading für akt. Verbrauch angegeben ?
      
      if (!$rpcurr && isConsumerPhysOn($hash, $c)) {                                           # Workaround wenn Verbraucher ohne Leistungsmessung
          $pcurr = $nompower;
      }
      
      my $currpowerpercent = $pcurr;    
      $currpowerpercent    = (($pcurr / $nompower) * 100) if($nompower > 0);
      
      $data{$type}{$name}{consumers}{$c}{currpowerpercent} = $currpowerpercent;
      
      my $starthour;
      if($pcurr > $ethreshold || $currpowerpercent > $defpopercent) {                          # Verbraucher ist aktiv
            if(ConsumerVal ($hash, $c, "onoff", "off") eq "off") {               
                $data{$type}{$name}{consumers}{$c}{startTime}       = $t;
                $data{$type}{$name}{consumers}{$c}{onoff}           = "on";
                my $stimes                                          = ConsumerVal ($hash, $c, "numberDayStarts", 0);     # Anzahl der On-Schaltungen am Tag
                $data{$type}{$name}{consumers}{$c}{numberDayStarts} = $stimes+1;
                $data{$type}{$name}{consumers}{$c}{lastMinutesOn}   = ConsumerVal ($hash, $c, "minutesOn", 0);               
            }
             
            $starthour = strftime "%H", localtime(ConsumerVal ($hash, $c, "startTime", $t)); 
        
            if($chour eq $starthour) {         
                my $runtime                                   = (($t - ConsumerVal ($hash, $c, "startTime", $t)) / 60);                  # in Minuten ! (gettimeofday sind ms !)          
                $data{$type}{$name}{consumers}{$c}{minutesOn} = ConsumerVal ($hash, $c, "lastMinutesOn", 0) + $runtime; 
            }
            else {                                                                                                               # neue Stunde hat begonnen
                if(ConsumerVal ($hash, $c, "onoff", "off") eq "on") {
                    $data{$type}{$name}{consumers}{$c}{startTime}     = timestringToTimestamp ($date." ".sprintf("%02d",$chour).":00:00");
                    $data{$type}{$name}{consumers}{$c}{minutesOn}     = ($t - ConsumerVal ($hash, $c, "startTime", $t)) / 60;                # in Minuten ! (gettimeofday sind ms !)                                                       
                    $data{$type}{$name}{consumers}{$c}{lastMinutesOn} = 0;
                }
            }                                                                                     
      }
      else {                                                                                  # Verbraucher soll nicht aktiv sein
          $data{$type}{$name}{consumers}{$c}{onoff} = "off";
          $starthour                                = strftime "%H", localtime(ConsumerVal ($hash, $c, "startTime", $t)); 
          
          if($chour ne $starthour) {
              $data{$type}{$name}{consumers}{$c}{minutesOn} = 0;
              delete $data{$type}{$name}{consumers}{$c}{startTime};
          }
      }
      
      $paref->{val}      = ConsumerVal ($hash, $c, "numberDayStarts", 0);                     # Anzahl Tageszyklen des Verbrauchers speichern
      $paref->{histname} = "cyclescsm${c}";
      setPVhistory ($paref);
      delete $paref->{histname};
      
      $paref->{val}      = ceil ConsumerVal ($hash, $c, "minutesOn", 0);                      # Verbrauchsminuten akt. Stunde des Consumers
      $paref->{histname} = "minutescsm${c}";
      setPVhistory ($paref);
      delete $paref->{histname};
      
      ## Durchschnittsverbrauch / Betriebszeit ermitteln + speichern
      ################################################################
      my $consumerco = 0;
      my $runhours   = 0;
      my $dnum       = 0;
      
      for my $n (sort{$a<=>$b} keys %{$data{$type}{$name}{pvhist}}) {                                             # Betriebszeit und gemessenen Verbrauch ermitteln
          my $csme  = HistoryVal ($hash, $n, 99, "csme${c}", 0);
          my $hours = HistoryVal ($hash, $n, 99, "hourscsme${c}", 0);
          next if(!$hours);
          
          $consumerco += $csme;
          $runhours   += $hours;
          $dnum++;      
      }
      
      if ($dnum) {  
          if($consumerco) {      
              $data{$type}{$name}{consumers}{$c}{avgenergy} = ceil ($consumerco/$dnum);                          # Durchschnittsverbrauch eines Tages aus History  
          }
          else {
              delete $data{$type}{$name}{consumers}{$c}{avgenergy};
          }
          
          $data{$type}{$name}{consumers}{$c}{avgruntime} = (ceil($runhours/$dnum)) * 60;                          # Durchschnittslaufzeit in Minuten 
      }
      
      $paref->{consumer} = $c;
      
      __calcEnergyPieces   ($paref);                                                                              # Energieverbrauch auf einzelne Stunden für Planungsgrundlage aufteilen
      __planSwitchTimes    ($paref);                                                                              # Consumer Switch Zeiten planen
      __setTimeframeState  ($paref);                                                                              # Timeframe Status ermitteln
      __setConsRcmdState   ($paref);                                                                              # Consumption Recommended Status setzen
      __switchConsumer     ($paref);                                                                              # Consumer schalten
      __remainConsumerTime ($paref);                                                                              # Restlaufzeit Verbraucher ermitteln
      
      ## Consumer Schaltstatus und Schaltzeit für Readings ermitteln 
      ################################################################
      my $costate = isConsumerPhysOn  ($hash, $c) ? "on"  : 
                    isConsumerPhysOff ($hash, $c) ? "off" :
                    "unknown";

      $data{$type}{$name}{consumers}{$c}{state} = $costate;
      
      my ($pstate,$starttime,$stoptime)         = __getPlanningStateAndTimes ($paref);
           
      push @$daref, "consumer${c}<>"              ."name='$alias' state='$costate' planningstate='$pstate' ";     # Consumer Infos 
      push @$daref, "consumer${c}_planned_start<>"."$starttime" if($starttime);                                   # Consumer Start geplant
      push @$daref, "consumer${c}_planned_stop<>". "$stoptime"  if($stoptime);                                    # Consumer Stop geplant            
  }
  
  delete $paref->{consumer};
    
return;
}

###################################################################
#    Energieverbrauch auf einzelne Stunden für Planungsgrundlage
#    aufteilen
#    Consumer specific epieces ermitteln + speichern
#    (in Wh)
###################################################################
sub __calcEnergyPieces {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $c     = $paref->{consumer}; 
  
  my $type  = $hash->{TYPE};
  
  my $etot = HistoryVal ($hash, $paref->{day}, sprintf("%02d",$paref->{nhour}), "csmt${c}", 0);
  
  if($etot) {
      $paref->{etot} = $etot;
      ___csmSpecificEpieces ($paref);
      delete $paref->{etot};
  }
  else {
      delete $data{$type}{$name}{consumers}{$c}{epiecAVG};
      delete $data{$type}{$name}{consumers}{$c}{epiecAVG_hours};
      delete $data{$type}{$name}{consumers}{$c}{epiecEstart};
      delete $data{$type}{$name}{consumers}{$c}{epiecHist};
      delete $data{$type}{$name}{consumers}{$c}{epiecHour};
      
      for my $h (1..$epiecHCounts) {
          delete $data{$type}{$name}{consumers}{$c}{"epiecHist_".$h};
          delete $data{$type}{$name}{consumers}{$c}{"epiecHist_".$h."_hours"};
      }
  }  

  delete $data{$type}{$name}{consumers}{$c}{epieces};
  
  my $cotype  = ConsumerVal ($hash, $c, "type",    $defctype  );
  my $mintime = ConsumerVal ($hash, $c, "mintime", $defmintime);
  my $hours   = ceil ($mintime / 60);                                                           # Laufzeit in h
  
  my $ctote   = ConsumerVal ($hash, $c, "avgenergy", undef);                                    # gemessener nominaler Energieverbrauch in Wh
  $ctote    //= ConsumerVal ($hash, $c, "power",         0);                                    # alternativer nominaler Energieverbrauch in Wh
  
  my $epiecef = $ctote * $hef{$cotype}{f};                                                      # Gewichtung erste Laufstunde
  my $epiecel = $ctote * $hef{$cotype}{l};                                                      # Gewichtung letzte Laufstunde
  
  my $epiecem = $ctote * $hef{$cotype}{m};
  
  for my $h (1..$hours) {
      my $he;
      $he = $epiecef                       if($h == 1               );                         # kalk. Energieverbrauch Startstunde
      $he = $epiecem                       if($h >  1 && $h < $hours);                         # kalk. Energieverbrauch Folgestunde(n)
      $he = $epiecel                       if($h == $hours          );                         # kalk. Energieverbrauch letzte Stunde
          
      $data{$type}{$name}{consumers}{$c}{epieces}{${h}} = sprintf('%.2f', $he);      
  }
  
return;
}

###################################################################
#  Verbraucherspezifische Energiestück Ermittlung
#
#  epiecHistCounts = x gibt an wie viele Zyklen betrachtet werden
#                      sollen
#  epiecHist => x ist der Index des Speicherbereichs der aktuell 
#               benutzt wird.
#
#  epiecHist_x => 1=x 2=x 3=x 4=x epieces eines Index
#  epiecHist_x_hours => x Stunden des Durchlauf bzw. wie viele 
#                         Einträge epiecHist_x hat
#  epiecAVG => 1=x 2=x und epiecAVG_hours => x enthalten die 
#              durchschnittlichen Werte der in epiecHistCounts 
#              vorgegebenen Durchläufe.
#
###################################################################
sub ___csmSpecificEpieces {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $c     = $paref->{consumer}; 
  my $etot  = $paref->{etot};
  my $t     = $paref->{t}; 
  
  my $type  = $hash->{TYPE};
   
  if(ConsumerVal ($hash, $c, "onoff", "off") eq "on") {                                                 # Status "Aus" verzögern um Pausen im Waschprogramm zu überbrücken
      $data{$type}{$name}{consumers}{$c}{lastOnTime} = $t;
  }
    
  my $offTime = defined $data{$type}{$name}{consumers}{$c}{lastOnTime} ? 
                $t - $data{$type}{$name}{consumers}{$c}{lastOnTime}    :
                99;

  if($offTime < 300) {                                                                                  # erst nach 60s ist das Gerät aus
      my $epiecHist        = "";
      my $epiecHist_hours  = "";
       
      if(ConsumerVal ($hash, $c, "epiecHour", -1) < 0) {                                                # neue Aufzeichnung
          $data{$type}{$name}{consumers}{$c}{epiecStartTime} = $t;
          $data{$type}{$name}{consumers}{$c}{epiecHist}     += 1;  
          $data{$type}{$name}{consumers}{$c}{epiecHist}      = 1 if(ConsumerVal ($hash, $c, "epiecHist", 0) > $epiecHCounts);
            
          $epiecHist = "epiecHist_".ConsumerVal ($hash, $c, "epiecHist", 0); 
          delete $data{$type}{$name}{consumers}{$c}{$epiecHist};                                        # Löschen, wird neu erfasst
      }
        
      $epiecHist       = "epiecHist_".ConsumerVal ($hash, $c, "epiecHist", 0);                          # Namen fürs Speichern
      $epiecHist_hours = "epiecHist_".ConsumerVal ($hash, $c, "epiecHist", 0)."_hours"; 
      my $epiecHour    = floor (($t - ConsumerVal ($hash, $c, "epiecStartTime", $t)) / 60 / 60) + 1;    # aktuelle Betriebsstunde ermitteln, ( / 60min) mögliche wäre auch durch 15min        /Minute /Stunde
            
      if(ConsumerVal ($hash, $c, "epiecHour", 0) != $epiecHour) {                                       # Stundenwechsel? Differenz von etot noch auf die vorherige Stunde anrechnen                       
          my $epiecHour_last = $epiecHour - 1;
          
          $data{$type}{$name}{consumers}{$c}{$epiecHist}{$epiecHour_last} = $etot - ConsumerVal ($hash, $c, "epiecEstart", 0) if($epiecHour > 1);
          $data{$type}{$name}{consumers}{$c}{epiecEstart}                 = $etot;        
      }
      
      my $ediff                                                  = $etot - ConsumerVal ($hash, $c, "epiecEstart", 0);
      $data{$type}{$name}{consumers}{$c}{$epiecHist}{$epiecHour} = $ediff;
      $data{$type}{$name}{consumers}{$c}{epiecHour}              = $epiecHour;
      $data{$type}{$name}{consumers}{$c}{$epiecHist_hours}       = $ediff ? $epiecHour : $epiecHour - 1; # wenn mehr als 1 Wh verbraucht wird die Stunde gezählt
  } 
  else {                                                                                                 # Durchschnitt ermitteln
      if(ConsumerVal ($hash, $c, "epiecHour", 0) > 0) {                                                  # Durchschnittliche Stunden ermitteln
          my $hours = 0;
          
          for my $h (1..$epiecHCounts) {                                                                 # durchschnittliche Stunden über alle epieces ermitteln und aufrunden
              $hours += ConsumerVal ($hash, $c, "epiecHist_".$h."_hours", 0);    
          }
            
          $hours                                             = ceil ($hours / $epiecHCounts);
          $data{$type}{$name}{consumers}{$c}{epiecAVG_hours} = $hours;
               
          delete $data{$type}{$name}{consumers}{$c}{epiecAVG};                                           # Durchschnitt für epics ermitteln     
          
          for my $hour (1..$hours) {                                                                     # jede Stunde durchlaufen
              my $hoursE = 1;
          
              for my $h (1..$epiecHCounts) {                                                             # jedes epiec durchlaufen
                  my $epiecHist = "epiecHist_".$h;
                  
                  if(defined $data{$type}{$name}{consumers}{$c}{$epiecHist}{$hour}) {
                      if($data{$type}{$name}{consumers}{$c}{$epiecHist}{$hour} > 5) {
                          $data{$type}{$name}{consumers}{$c}{epiecAVG}{$hour} += $data{$type}{$name}{consumers}{$c}{$epiecHist}{$hour}; 
                          $hoursE += 1;
                      }
                  }
                  
              }
              
              my $eavg = defined $data{$type}{$name}{consumers}{$c}{epiecAVG}{$hour} ? 
                         $data{$type}{$name}{consumers}{$c}{epiecAVG}{$hour}         :
                         0;
                         
              $data{$type}{$name}{consumers}{$c}{epiecAVG}{$hour} = sprintf('%.2f', $eavg / $hoursE);    # Durchschnitt ermittelt und in epiecAVG schreiben
          }
      }
    
      $data{$type}{$name}{consumers}{$c}{epiecHour} = -1;                                                # epiecHour auf initialwert setzen für nächsten durchlauf
  }
  
return;
}

###################################################################
#    Consumer Schaltzeiten planen
###################################################################
sub __planSwitchTimes {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $c     = $paref->{consumer};
  
  return if(ConsumerVal ($hash, $c, "planstate", undef));                                  # Verbraucher ist schon geplant/gestartet/fertig
  
  my $type   = $hash->{TYPE};
  my $debug  = AttrVal ($name, "debug", 0);
  
  my $nh     = $data{$type}{$name}{nexthours};
  my $maxkey = (scalar keys %{$data{$type}{$name}{nexthours}}) - 1;
  my %max;
  my %mtimes;
  
  ## max. Überschuß ermitteln
  #############################
  for my $idx (sort keys %{$nh}) {
      my $pvfc    = NexthoursVal ($hash, $idx, "pvforecast", 0 );
      my $confc   = NexthoursVal ($hash, $idx, "confc",      0 );
      my $surplus = $pvfc-$confc;                                                          # Energieüberschuß (kann negativ sein)
      # next if($surplus <= 0);
      
      my ($hour) = $idx =~ /NextHour(\d+)/xs;
      $max{$surplus}{starttime} = NexthoursVal ($hash, $idx, "starttime", "");
      $max{$surplus}{today}     = NexthoursVal ($hash, $idx, "today",      0);
      $max{$surplus}{nexthour}  = int ($hour);
  }
  
  my $order = 1;
  for my $k (reverse sort{$a<=>$b} keys %max) {
      $max{$order}{surplus}   = $k;
      $max{$order}{starttime} = $max{$k}{starttime};
      $max{$order}{nexthour}  = $max{$k}{nexthour};
      $max{$order}{today}     = $max{$k}{today};
      
      my $ts = timestringToTimestamp ($max{$k}{starttime});
      $mtimes{$ts}{surplus}   = $k;
      $mtimes{$ts}{starttime} = $max{$k}{starttime};
      $mtimes{$ts}{nexthour}  = $max{$k}{nexthour};
      $mtimes{$ts}{today}     = $max{$k}{today};
      
      delete $max{$k};
      
      $order++;
  }
  
  my $epiece1 = (~0 >> 1);
  my $epieces = ConsumerVal ($hash, $c, "epieces", "");
  
  if(ref $epieces eq "HASH") {
      $epiece1 = $data{$type}{$name}{consumers}{$c}{epieces}{1};
  }
  else {
      return;
  }
  
  if($debug) {                                                                                         # nur für Debugging
      Log (1, "DEBUG> $name - consumer: $c, epiece1: $epiece1");
  }
  
  my $mode     = ConsumerVal ($hash, $c, "mode",          "can");
  my $calias   = ConsumerVal ($hash, $c, "alias",            "");
  my $mintime  = ConsumerVal ($hash, $c, "mintime", $defmintime);
  my $stopdiff = ceil($mintime / 60) * 3600;
  
  $paref->{maxref}   = \%max;
  $paref->{mintime}  = $mintime;
  $paref->{stopdiff} = $stopdiff;
  
  if($mode eq "can") {                                                                                 # Verbraucher kann geplant werden
      if($debug) {                                                                                     # nur für Debugging
          Log (1, "DEBUG> $name - consumer: $c, mode: $mode, relevant hash: mtimes");
          for my $m (sort{$a<=>$b} keys %mtimes) {                                                   
              Log (1, "DEBUG> $name - hash: mtimes, surplus: $mtimes{$m}{surplus}, starttime: $mtimes{$m}{starttime}, nexthour: $mtimes{$m}{nexthour}, today: $mtimes{$m}{today}"); 
          }
      }
      
      for my $ts (sort{$a<=>$b} keys %mtimes) {
          if($mtimes{$ts}{surplus} >= $epiece1) {                                                      # die früheste Startzeit sofern Überschuß größer als Bedarf 
              my $starttime       = $mtimes{$ts}{starttime};
              $paref->{starttime} = $starttime;
              $starttime          = ___switchonTimelimits ($paref);
              
              delete $paref->{starttime};
              
              my $startts       = timestringToTimestamp ($starttime);                                  # Unix Timestamp für geplanten Switch on

              $paref->{ps}      = "planned:";
              $paref->{startts} = $startts;
              $paref->{stopts}  = $startts + $stopdiff;

              ___setConsumerPlanningState ($paref);

              delete $paref->{ps};
              delete $paref->{startts};
              delete $paref->{stopts};                
              
              last;
          }
          else {
              $paref->{ps} = "no planning: the max expected surplus is less $epiece1";

              ___setConsumerPlanningState ($paref);
              
              delete $paref->{ps};
          }
      }   
  }
  else {                                                                                               # Verbraucher _muß_ geplant werden
      if($debug) {                                                                                     # nur für Debugging
          Log (1, "DEBUG> $name - consumer: $c, mode: $mode, relevant hash: max");
          for my $o (sort{$a<=>$b} keys %max) {                                                   
              Log (1, "DEBUG> $name - hash: max, surplus: $max{$o}{surplus}, starttime: $max{$o}{starttime}, nexthour: $max{$o}{nexthour}, today: $max{$o}{today}"); 
          }
      }
      
      for my $o (sort{$a<=>$b} keys %max) {
          next if(!$max{$o}{today});                                                                   # der max-Wert ist _nicht_ heute
          $paref->{elem} = $o;
          ___planMust ($paref);        
          last;
      }

      if(!ConsumerVal ($hash, $c, "planstate", undef)) {                                               # es konnte keine Planung mit max für den aktuellen Tag erstellt werden -> Zwangsplanung mit ersten Wert
              my $p = (sort{$a<=>$b} keys %max)[0];
              $paref->{elem} = $p;
              ___planMust ($paref);
      }              
  }
  
  my $planstate = ConsumerVal ($hash, $c, "planstate", "");
  
  writeDataToFile ($hash, "consumers", $csmcache.$name);                                               # Cache File Consumer schreiben
  
  Log3 ($name, 3, qq{$name - Consumer "$calias" $planstate}) if($planstate);
  
return;
}

################################################################
#     Planungsdaten bzw. aktuelle Planungszustände setzen  
################################################################
sub ___setConsumerPlanningState {     
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $c       = $paref->{consumer};
  my $ps      = $paref->{ps};                                                # Planstatus
  my $startts = $paref->{startts};                                           # Unix Timestamp für geplanten Switch on 
  my $stopts  = $paref->{stopts};                                            # Unix Timestamp für geplanten Switch off
  
  my $type    = $hash->{TYPE};
  my $name    = $hash->{NAME};
  
  my ($starttime,$stoptime);
  
  if ($startts) {
      (undef,undef,undef,$starttime)                   = timestampToTimestring ($startts);
      $data{$type}{$name}{consumers}{$c}{planswitchon} = $startts; 
  }
  
  if ($stopts) {
      (undef,undef,undef,$stoptime)                     = timestampToTimestring ($stopts);
      $data{$type}{$name}{consumers}{$c}{planswitchoff} = $stopts; 
  }
  
  #my $pstate = simplifyCstate ($ps);
  #my $swtime = "";
  #if ($pstate eq "started") {
  #    ($swtime, $startts) = lastConsumerSwitchtime ($hash, $c);
  #    Log3 ($hash->{NAME}, 1, "$hash->{NAME} - $c, swtime: $swtime, startts: $startts");
  #}
  #elsif ($pstate eq "finished") {
  #    ($swtime, $stopts)  = lastConsumerSwitchtime ($hash, $c);
  #   Log3 ($hash->{NAME}, 1, "$hash->{NAME} - $c, swtime: $swtime, stopts:$stopts ");
  #}
  
  $ps .= " "              if ($starttime || $stoptime);
  $ps .= $starttime       if ($starttime);
  $ps .= $stoptime        if (!$starttime && $stoptime);
  $ps .= " - ".$stoptime  if ($starttime  && $stoptime);
                                  
  $data{$type}{$name}{consumers}{$c}{planstate} = $ps; 
  
return;
}

################################################################
#          Consumer Zeiten MUST planen
################################################################
sub ___planMust {
  my $paref    = shift;
  my $hash     = $paref->{hash};
  my $name     = $paref->{name};
  my $c        = $paref->{consumer};
  my $maxref   = $paref->{maxref};
  my $elem     = $paref->{elem};
  my $mintime  = $paref->{mintime};
  my $stopdiff = $paref->{stopdiff};

  my $type     = $hash->{TYPE};

  my $maxts                         = timestringToTimestamp ($maxref->{$elem}{starttime});           # Unix Timestamp des max. Überschusses heute
  my $half                          = ceil ($mintime / 2 / 60);                                      # die halbe Gesamtlaufzeit in h als Vorlaufzeit einkalkulieren   
  my $startts                       = $maxts - ($half * 3600); 
  my (undef,undef,undef,$starttime) = timestampToTimestring ($startts);
  
  $paref->{starttime}               = $starttime;
  $starttime                        = ___switchonTimelimits ($paref);
  delete $paref->{starttime};
  
  $startts                          = timestringToTimestamp ($starttime);
  my $stopts                        = $startts + $stopdiff;
  
  $paref->{ps}      = "planned:";
  $paref->{startts} = $startts;                                                                       # Unix Timestamp für geplanten Switch on       
  $paref->{stopts}  = $stopts;                                                                        # Unix Timestamp für geplanten Switch off

  ___setConsumerPlanningState ($paref);

  delete $paref->{ps};
  delete $paref->{startts};
  delete $paref->{stopts};

return;
}

################################################################
#   Einschaltgrenzen berücksichtigen und Korrektur 
#   zurück liefern
################################################################
sub ___switchonTimelimits {
  my $paref     = shift;
  my $hash      = $paref->{hash};
  my $name      = $paref->{name};
  my $c         = $paref->{consumer};
  my $starttime = $paref->{starttime};

  my $origtime    = $starttime;
  my $notbefore   = ConsumerVal ($hash, $c, "notbefore", 0);
  my $notafter    = ConsumerVal ($hash, $c, "notafter",  0);
  my ($starthour) = $starttime =~ /\s(\d{2}):/xs;
  
  my $change = q{};
  
  if($notbefore && int $starthour < int $notbefore) {
      $starthour = $notbefore;
      $change    = "notbefore";
  }
  
  if($notafter && int $starthour > int $notafter) {
      $starthour = $notafter;
      $change    = "notafter";
  } 
  
  $starthour = sprintf("%02d", $starthour);
  $starttime =~ s/\s(\d{2}):/ $starthour:/x;             
  
  if($change) {
      my $cname = ConsumerVal ($hash, $c, "name", "");
      Log3 ($name, 3, qq{$name - Planned starttime "$cname" changed from "$origtime" to "$starttime" due to $change condition});
  }

return $starttime;
}

################################################################
#   Timeframe Status ermitteln
################################################################
sub __setTimeframeState {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $c     = $paref->{consumer};
  my $t     = $paref->{t};                                                            # aktueller Unixtimestamp
  
  my $type  = $hash->{TYPE};

  my $startts = ConsumerVal ($hash, $c, "planswitchon",  undef);                      # geplante Unix Startzeit
  my $stopts  = ConsumerVal ($hash, $c, "planswitchoff", undef);                      # geplante Unix Stopzeit  
  
  if ($startts && $t >= $startts && $stopts && $t <= $stopts) {                       # ist Zeit innerhalb der Planzeit ein/aus ?
      $data{$type}{$name}{consumers}{$c}{isIntimeframe} = 1;
  } 
  else {
      $data{$type}{$name}{consumers}{$c}{isIntimeframe} = 0;
  }
  
return;
}

################################################################
#   Consumption Recommended Status setzen
################################################################
sub __setConsRcmdState {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $c     = $paref->{consumer};                                                     # aktueller Unixtimestamp
  my $daref = $paref->{daref};
  
  my $type  = $hash->{TYPE};

  my $surplus  = CurrentVal  ($hash, "surplus",   0);                                 # aktueller Energieüberschuß
  my $nompower = ConsumerVal ($hash, $c, "power", 0);                                 # Consumer nominale Leistungsaufnahme (W)
  my $ccr      = AttrVal     ($name, 'createConsumptionRecReadings', '');             # Liste der Consumer für die ConsumptionRecommended-Readings erstellt werden sollen
  
  if ($surplus >= $nompower) {
      $data{$type}{$name}{consumers}{$c}{isConsumptionRecommended} = 1;               # Einschalten des Consumers günstig
  }
  else {
      $data{$type}{$name}{consumers}{$c}{isConsumptionRecommended} = 0;
  }
  
  if ($ccr =~ /$c/xs) {
      push @$daref, "consumer${c}_ConsumptionRecommended<>". ConsumerVal ($hash, $c, 'isConsumptionRecommended', 0); 
  }
  
return;
}

################################################################
#   Planungsdaten Consumer prüfen und ggf. starten/stoppen
################################################################
sub __switchConsumer {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $c     = $paref->{consumer};
  my $t     = $paref->{t};                                                           # aktueller Unixtimestamp
  my $state = $paref->{state};
  
  my $type  = $hash->{TYPE};
  
  $state    = ___switchConsumerOn          ($paref);                                 # Verbraucher Einschaltbedingung prüfen + auslösen 
  $state    = ___switchConsumerOff         ($paref);                                 # Verbraucher Ausschaltbedingung prüfen + auslösen
  $state    = ___setConsumerSwitchingState ($paref);                                 # Consumer aktuelle Schaltzustände ermitteln & setzen 
  
  $paref->{state} = $state;
  
return;
}

################################################################
#  Verbraucher einschalten
################################################################
sub ___switchConsumerOn {
  my $paref = shift; 
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $c     = $paref->{consumer};
  my $t     = $paref->{t};                                                                        # aktueller Unixtimestamp
  my $state = $paref->{state};
  
  my $debug   = AttrVal     ($name, "debug",                 0);
  my $pstate  = ConsumerVal ($hash, $c, "planstate",        "");
  my $startts = ConsumerVal ($hash, $c, "planswitchon",  undef);                                  # geplante Unix Startzeit
  my $oncom   = ConsumerVal ($hash, $c, "oncom",            "");                                  # Set Command für "on"
  my $auto    = ConsumerVal ($hash, $c, "auto",              1);
  my $cname   = ConsumerVal ($hash, $c, "name",             "");                                  # Consumer Device Name
  my $calias  = ConsumerVal ($hash, $c, "alias",            "");                                  # Consumer Device Alias
  
  my ($swoncond,$info,$err) = isAddSwitchOnCond ($hash, $c);                                      # zusätzliche Switch on Bedingung

  Log3 ($name, 1, "$name - $err") if($err);
  
  if ($debug) {                                                                                   # nur für Debugging
      Log (1, qq{DEBUG> $name - Parameters for switch on decision consumer "$c": }.
              qq{swoncond: $swoncond, auto mode: $auto, on-command: $oncom, }.
              qq{planning state: $pstate, start timestamp: }.($startts ? $startts : "undef").", ".
              qq{timestamp: $t}              
           );
  }
 
  if ($swoncond && $auto && $oncom && 
      simplifyCstate($pstate) =~ /planned|priority|starting/xs && 
      isInTimeframe ($hash, $c)) {                                                                # Verbraucher Start ist geplant && Startzeit überschritten
      my $mode    = ConsumerVal ($hash, $c, "mode", $defcmode);                                   # Consumer Planungsmode
      my $enable  = ___enableSwitchByBatPrioCharge ($paref);                                      # Vorrangladung Batterie ?
      
      Log3 ($name, 4, "$name - Consumer switch enabled by battery: $enable");  
      
      if ($mode eq "can" && !$enable) {                                                           # Batterieladung - keine Verbraucher "Einschalten" Freigabe
          $paref->{ps} = "priority charging battery";

        ___setConsumerPlanningState ($paref);

        delete $paref->{ps};
      }
      elsif ($mode eq "must" || isConsRcmd($hash, $c)) {                                          # "Muss"-Planung oder Überschuß > Leistungsaufnahme
          CommandSet(undef,"$cname $oncom");
          my $stopdiff = ceil(ConsumerVal ($hash, $c, "mintime", $defmintime) / 60) * 3600;
          
          $paref->{ps} = "switching on:";

          ___setConsumerPlanningState ($paref);

          delete $paref->{ps};
          
          $state = qq{switching Consumer "$calias" to "$oncom"};
          
          writeDataToFile ($hash, "consumers", $csmcache.$name);                                  # Cache File Consumer schreiben
          
          Log3 ($name, 2, "$name - $state (Automatic = $auto)");
      }
  }
  elsif (isInterruptible($hash, $c) && isConsRcmd     ($hash, $c)  &&                             # unterbrochenen Consumer fortsetzen
         isInTimeframe  ($hash, $c) && simplifyCstate ($pstate) =~ /interrupted|interrupting/xs &&
         $auto && $oncom) {
 
      CommandSet(undef,"$cname $oncom");
      
      $paref->{ps} = "continuing:";

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};
      
      $state = qq{switching Consumer "$calias" to "$oncom", caution: continuing by surplus};
      
      writeDataToFile ($hash, "consumers", $csmcache.$name);                                               # Cache File Consumer schreiben
      
      Log3 ($name, 2, "$name - $state");
  }

return $state;
}

################################################################
#  Verbraucher ausschalten
################################################################
sub ___switchConsumerOff {
  my $paref = shift; 
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $c     = $paref->{consumer};
  my $t     = $paref->{t};                                                                        # aktueller Unixtimestamp
  my $state = $paref->{state};
  
  my $debug   = AttrVal     ($name, "debug",                 0);
  my $pstate  = ConsumerVal ($hash, $c, "planstate",        "");
  my $stopts  = ConsumerVal ($hash, $c, "planswitchoff", undef);                                  # geplante Unix Stopzeit
  my $auto    = ConsumerVal ($hash, $c, "auto",              1);
  my $cname   = ConsumerVal ($hash, $c, "name",             "");                                  # Consumer Device Name
  my $calias  = ConsumerVal ($hash, $c, "alias",            "");                                  # Consumer Device Alias
  my $mode    = ConsumerVal ($hash, $c, "mode",      $defcmode);                                  # Consumer Planungsmode
  
  my $offcom                 = ConsumerVal        ($hash, $c, "offcom", "");                      # Set Command für "off"
  my ($swoffcond,$info,$err) = isAddSwitchOffCond ($hash, $c);                                    # zusätzliche Switch on Bedingung

  Log3 ($name, 1, "$name - $err") if($err);
  
  if($debug) {                                                                                    # nur für Debugging
      Log (1, qq{DEBUG> $name - Parameters for switch off decision consumer "$c": }.
              qq{swoffcond: $swoffcond, auto mode: $auto, off-command: $offcom, }.
              qq{planning state: $pstate, stop timestamp: }.($stopts ? $stopts : "undef").", ".
              qq{timestamp: $t}              
           );
  }
  
  if(($swoffcond || ($stopts && $t >= $stopts)) && 
     ($auto && $offcom && simplifyCstate($pstate) =~ /started|starting|stopping|interrupt|continu/xs)) {                         
      CommandSet(undef,"$cname $offcom");
      
      $paref->{ps} = "switching off:";

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};      
      
      my $caution = $swoffcond ? "switch-off condition (key swoffcond) is true" : "planned switch-off time reached/exceeded";
      $state      = qq{switching Consumer "$calias" to "$offcom", caution: $caution};
      
      writeDataToFile ($hash, "consumers", $csmcache.$name);                                               # Cache File Consumer schreiben
      
      Log3 ($name, 2, "$name - $state (Automatic = $auto)");
  }
  elsif (isInterruptible($hash, $c) && !isConsRcmd    ($hash, $c) && $mode eq 'can' &&                     # Consumer unterbrechen 
         isInTimeframe  ($hash, $c) && simplifyCstate ($pstate) =~ /started|continued|interrupting/xs &&
         $auto && $offcom) {
 
      CommandSet(undef,"$cname $offcom");
      
      $paref->{ps} = "interrupting:";

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};
      
      $state = qq{switching Consumer "$calias" to "$offcom", caution: surplus shortage};
      
      writeDataToFile ($hash, "consumers", $csmcache.$name);                                               # Cache File Consumer schreiben
      
      Log3 ($name, 2, "$name - $state");
  }
  
return $state;
}

################################################################
#     Consumer aktuelle Schaltzustände ermitteln & setzen  
#     Consumer "on" setzen wenn physisch ein und alter Status 
#     "starting"
#     Consumer "off" setzen wenn physisch aus und alter Status 
#     "stopping"
################################################################
sub ___setConsumerSwitchingState {     
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $c     = $paref->{consumer};
  my $t     = $paref->{t};
  my $state = $paref->{state};
  
  my $type  = $hash->{TYPE};
  my $name  = $hash->{NAME};
  
  my $pstate = simplifyCstate (ConsumerVal ($hash, $c, "planstate", ""));
  my $calias = ConsumerVal    ($hash, $c, "alias", "");                                      # Consumer Device Alias
  my $auto   = ConsumerVal    ($hash, $c, "auto",   1);
  
  if ($pstate eq 'starting' && isConsumerPhysOn ($hash, $c)) {
      my $stopdiff      = ceil(ConsumerVal ($hash, $c, "mintime", $defmintime) / 60) * 3600;
      
      $paref->{ps}      = "switched on:";
      $paref->{startts} = $t;
      $paref->{stopts}  = $t + $stopdiff;

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};
      delete $paref->{startts};
      delete $paref->{stopts};
      
      $state = qq{Consumer "$calias" switched on};
      
      writeDataToFile ($hash, "consumers", $csmcache.$name);                                  # Cache File Consumer schreiben
      
      Log3 ($name, 2, "$name - $state (Automatic = $auto)");
  }
  elsif ($pstate eq 'stopping' && isConsumerPhysOff ($hash, $c)) {
      $paref->{ps}     = "switched off:";
      $paref->{stopts} = $t;

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};
      delete $paref->{stopts};      
      
      $state = qq{Consumer "$calias" switched off};
      
      writeDataToFile ($hash, "consumers", $csmcache.$name);                                 # Cache File Consumer schreiben
      
      Log3 ($name, 2, "$name - $state (Automatic = $auto)");      
  }
  elsif ($pstate eq 'continuing' && isConsumerPhysOn ($hash, $c)) {
      $paref->{ps} = "continued:";

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};     
      
      $state = qq{Consumer "$calias" switched on (continued)};
      
      writeDataToFile ($hash, "consumers", $csmcache.$name);                                 # Cache File Consumer schreiben
      
      Log3 ($name, 2, "$name - $state");      
  }
  elsif ($pstate eq 'interrupting' && isConsumerPhysOff ($hash, $c)) {
      $paref->{ps} = "interrupted:";

      ___setConsumerPlanningState ($paref);

      delete $paref->{ps};     
      
      $state = qq{Consumer "$calias" switched off (interrupted)};
      
      writeDataToFile ($hash, "consumers", $csmcache.$name);                                 # Cache File Consumer schreiben
      
      Log3 ($name, 2, "$name - $state");      
  }
  
return $state;
}

################################################################
#   Restlaufzeit Verbraucher ermitteln
################################################################
sub __remainConsumerTime {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $c     = $paref->{consumer};
  my $t     = $paref->{t};                                                                   # aktueller Unixtimestamp
  
  my $type  = $hash->{TYPE};
  
  my ($planstate,$startstr,$stoptstr) = __getPlanningStateAndTimes ($paref);
  my $stopts                          = ConsumerVal ($hash, $c, "planswitchoff", undef);     # geplante Unix Stopzeit  
  
  $data{$type}{$name}{consumers}{$c}{remainTime} = 0;
  
  if (isInTimeframe($hash, $c) && (($planstate =~ /started/xs && isConsumerPhysOn($hash, $c)) | $planstate =~ /interrupt|continu/xs)) {  
      my $remainTime                                 = $stopts - $t ;
      $data{$type}{$name}{consumers}{$c}{remainTime} = sprintf "%.0f", ($remainTime / 60) if($remainTime > 0);
  }
  
return;
}

################################################################
# Freigabe Einschalten Verbraucher durch Batterie Vorrangladung 
#    return 0 -> keine Einschaltfreigabe Verbraucher
#    return 1 -> Einschaltfreigabe Verbraucher
################################################################
sub ___enableSwitchByBatPrioCharge {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $c     = $paref->{consumer};
  
  my $ena     = 1;
  my $pcb     = AttrVal ($name, "preferredChargeBattery", 0);                # Vorrangladung Batterie zu X%
  my ($badev) = useBattery ($name);
  
  return $ena if(!$pcb || !$badev);                                          # Freigabe Schalten Consumer wenn kein Prefered Battery/Soll-Ladung 0 oder keine Batterie installiert
  
  my $cbcharge = CurrentVal ($hash, "batcharge", 0);                         # aktuelle Batterieladung
  $ena         = 0 if($cbcharge < $pcb);                                     # keine Freigabe wenn Batterieladung kleiner Soll-Ladung

return $ena;
}

###################################################################
#    Consumer Planstatus und Planzeit ermitteln
###################################################################
sub __getPlanningStateAndTimes {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $c     = $paref->{consumer};
  
  my $pstate  = ConsumerVal    ($hash, $c, "planstate", "");      
  $pstate     = simplifyCstate ($pstate);
  
  my $startts = ConsumerVal ($hash, $c, "planswitchon",  "");
  my $stopts  = ConsumerVal ($hash, $c, "planswitchoff", "");
  
  my $starttime = '';
  my $stoptime  = '';
  $starttime    = timestampToTimestring ($startts) if($startts);
  $stoptime     = timestampToTimestring ($stopts)  if($stopts);
  
return ($pstate,$starttime,$stoptime);
}

################################################################
#                    Batteriewerte sammeln
################################################################
sub _transferBatteryValues {               
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $chour = $paref->{chour};
  my $day   = $paref->{day};
  my $daref = $paref->{daref};  

  my ($badev,$a,$h) = useBattery ($name);
  return if(!$badev);
  
  my $type = $hash->{TYPE}; 
  
  my ($pin,$piunit)    = split ":", $h->{pin};                                                # Readingname/Unit für aktuelle Batterieladung
  my ($pou,$pounit)    = split ":", $h->{pout};                                               # Readingname/Unit für aktuelle Batterieentladung
  my ($bin,$binunit)   = split ":", $h->{intotal}  // "-:-";                                  # Readingname/Unit der total in die Batterie eingespeisten Energie (Zähler)
  my ($bout,$boutunit) = split ":", $h->{outtotal} // "-:-";                                  # Readingname/Unit der total aus der Batterie entnommenen Energie (Zähler)
  my $batchr           = $h->{charge} // "";                                                  # Readingname Ladezustand Batterie
  
  return if(!$pin || !$pou);
  
  $pounit   //= $piunit;
  $piunit   //= $pounit;
  $boutunit //= $binunit;
  $binunit  //= $boutunit;
  
  Log3 ($name, 5, "$name - collect Battery data: device=$badev, pin=$pin ($piunit), pout=$pou ($pounit), totalin: $bin ($binunit), totalout: $bout ($boutunit), charge: $batchr");
  
  my $piuf      = $piunit   =~ /^kW$/xi  ? 1000 : 1;
  my $pouf      = $pounit   =~ /^kW$/xi  ? 1000 : 1;
  my $binuf     = $binunit  =~ /^kWh$/xi ? 1000 : 1;
  my $boutuf    = $boutunit =~ /^kWh$/xi ? 1000 : 1;  
  
  my $pbo       = ReadingsNum ($badev, $pou,    0) * $pouf;                                    # aktuelle Batterieentladung (W)
  my $pbi       = ReadingsNum ($badev, $pin,    0) * $piuf;                                    # aktueller Batterieladung (W)
  my $btotout   = ReadingsNum ($badev, $bout,   0) * $boutuf;                                  # totale Batterieentladung (Wh)
  my $btotin    = ReadingsNum ($badev, $bin,    0) * $binuf;                                   # totale Batterieladung (Wh)
  my $batcharge = ReadingsNum ($badev, $batchr, 0);
  
  my $params;
  
  if ($pin eq "-pout") {                                                                       # Spezialfall pin bei neg. pout
      $params = {
          dev  => $badev,
          rdg  => $pou,
          rdgf => $pouf
      };     
      
      ($pbo,$pbi) = substSpecialCases ($params);   
  }
  
  if ($pou eq "-pin") {                                                                        # Spezialfall pout bei neg. pin
      $params = {
          dev  => $badev,
          rdg  => $pin,
          rdgf => $piuf
      };     
      
      ($pbi,$pbo) = substSpecialCases ($params);
  }

  my $nhour        = $chour+1; 

######

  my $histbatintot = HistoryVal ($hash, $day, sprintf("%02d",$nhour), "batintotal", undef);   # totale Betterieladung zu Beginn einer Stunde
  
  my $batinthishour;
  if(!defined $histbatintot) {                                                                # totale Betterieladung der aktuelle Stunde gesetzt ?                                          
      $paref->{batintotal} = $btotin;
      $paref->{nhour}      = sprintf("%02d",$nhour);
      $paref->{histname}   = "batintotal";
      setPVhistory ($paref);
      delete $paref->{histname};
      
      my $bitot      = CurrentVal ($hash, "batintotal", $btotin);  
      $batinthishour = int ($btotin - $bitot);
  }
  else {
      $batinthishour = int ($btotin - $histbatintot);
  }

  if($batinthishour < 0) {
      $batinthishour = 0;
  }
  
  $data{$type}{$name}{circular}{sprintf("%02d",$nhour)}{batin} = $batinthishour;                # Ringspeicher Battery In Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350
  
  $paref->{batinthishour} = $batinthishour;
  $paref->{nhour}         = sprintf("%02d",$nhour);
  $paref->{histname}      = "batinthishour";
  setPVhistory ($paref);
  delete $paref->{histname};

######

  my $histbatouttot = HistoryVal ($hash, $day, sprintf("%02d",$nhour), "batouttotal", undef);   # totale Betterieladung zu Beginn einer Stunde
  
  my $batoutthishour;
  if(!defined $histbatouttot) {                                                                 # totale Betterieladung der aktuelle Stunde gesetzt ?                                          
      $paref->{batouttotal} = $btotout;
      $paref->{nhour}       = sprintf("%02d",$nhour);
      $paref->{histname}    = "batouttotal";
      setPVhistory ($paref);
      delete $paref->{histname};
      
      my $botot       = CurrentVal ($hash, "batouttotal", $btotout);  
      $batoutthishour = int ($btotout - $botot);
  }
  else {
      $batoutthishour = int ($btotout - $histbatouttot);
  }

  if($batoutthishour < 0) {
      $batoutthishour = 0;
  }
  
  $data{$type}{$name}{circular}{sprintf("%02d",$nhour)}{batout} = $batoutthishour;             # Ringspeicher Battery In Forum: https://forum.fhem.de/index.php/topic,117864.msg1133350.html#msg1133350
  
  $paref->{batoutthishour} = $batoutthishour;
  $paref->{nhour}          = sprintf("%02d",$nhour);
  $paref->{histname}       = "batoutthishour";
  setPVhistory ($paref);
  delete $paref->{histname};
  
######
  
  push @$daref, "Today_Hour".sprintf("%02d",$nhour)."_BatIn<>". $batinthishour. " Wh";
  push @$daref, "Today_Hour".sprintf("%02d",$nhour)."_BatOut<>".$batoutthishour." Wh";  
  push @$daref, "Current_PowerBatIn<>". (int $pbi)." W";
  push @$daref, "Current_PowerBatOut<>".(int $pbo)." W";
  push @$daref, "Current_BatCharge<>".  $batcharge." %";
  
  $data{$type}{$name}{current}{powerbatin}  = int $pbi;                                       # Hilfshash Wert aktuelle Batterieladung
  $data{$type}{$name}{current}{powerbatout} = int $pbo;                                       # Hilfshash Wert aktuelle Batterieentladung
  $data{$type}{$name}{current}{batintotal}  = int $btotin;                                    # totale Batterieladung
  $data{$type}{$name}{current}{batouttotal} = int $btotout;                                   # totale Batterieentladung
  $data{$type}{$name}{current}{batcharge}   = $batcharge;                                     # aktuelle Batterieladung
  
return;
}

################################################################
#     Energieverbrauch Vorhersage kalkulieren
#     
#     Es werden nur gleiche Wochentage (Mo ... So) 
#     zusammengefasst und der Durchschnitt ermittelt als 
#     Vorhersage
################################################################
sub _estConsumptionForecast {
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $chour   = $paref->{chour}; 
  my $t       = $paref->{t};
  my $day     = $paref->{day};                                                      # aktuelles Tagdatum (01...31)
  my $dayname = $paref->{dayname};                                                  # aktueller Tagname
  
  my $medev    = ReadingsVal ($name, "currentMeterDev", "");                        # aktuelles Meter device
  my $swdfcfc  = AttrVal     ($name, "sameWeekdaysForConsfc", 0);                   # nutze nur gleiche Wochentage (Mo...So) für Verbrauchsvorhersage
  my ($am,$hm) = parseParams ($medev);
  $medev       = $am->[0] // "";
  return if(!$medev || !$defs{$medev});
  
  my $type  = $hash->{TYPE};
  
  my $acref = $data{$type}{$name}{consumers};
 
  ## Verbrauchsvorhersage für den nächsten Tag
  ##############################################
  my $tomorrow   = strftime "%a", localtime($t+86400);                                                  # Wochentagsname kommender Tag
  my $totcon     = 0;
  my $dnum       = 0;
  my $consumerco = 0;
  my $min        =  (~0 >> 1);
  my $max        = -(~0 >> 1);
  
  for my $n (sort{$a<=>$b} keys %{$data{$type}{$name}{pvhist}}) {
      next if ($n eq $dayname);                                                                         # aktuellen (unvollständigen) Tag nicht berücksichtigen
      
      if ($swdfcfc) {                                                                                   # nur gleiche Tage (Mo...So) einbeziehen
          my $hdn = HistoryVal ($hash, $n, 99, "dayname", undef);
          next if(!$hdn || $hdn ne $tomorrow);
      }
      
      my $dcon = HistoryVal ($hash, $n, 99, "con", 0);
      next if(!$dcon);

      for my $c (sort{$a<=>$b} keys %{$acref}) {                                                        # Verbrauch aller registrierten Verbraucher aufaddieren
          $consumerco += HistoryVal ($hash, $n, 99, "csme${c}", 0);
      }
      
      $dcon -= $consumerco if($dcon >= $consumerco);                                                    # Verbrauch registrierter Verbraucher aus Verbrauch eliminieren
    
      $min  = $dcon if($dcon < $min);
      $max  = $dcon if($dcon > $max);
      
      $totcon += $dcon;
      $dnum++;      
  }
  
  if ($dnum) {
       my $ddiff                                         = ($max - $min)/$dnum;                          # Glättungsdifferenz
       my $tomavg                                        = int (($totcon/$dnum)-$ddiff);
       $data{$type}{$name}{current}{tomorrowconsumption} = $tomavg;                                      # Durchschnittsverbrauch aller (gleicher) Wochentage
    
       Log3 ($name, 4, "$name - estimated Consumption for tomorrow: $tomavg, days for avg: $dnum, hist. consumption registered consumers: ".sprintf "%.2f", $consumerco);
  }
  else {
      $data{$type}{$name}{current}{tomorrowconsumption} = "Wait for more days with a consumption figure";
  }
  
  ## Verbrauchsvorhersage für die nächsten Stunden
  ##################################################
  my $conh = { "01" => 0, "02" => 0, "03" => 0, "04" => 0,
               "05" => 0, "06" => 0, "07" => 0, "08" => 0,
               "09" => 0, "10" => 0, "11" => 0, "12" => 0,
               "13" => 0, "14" => 0, "15" => 0, "16" => 0,
               "17" => 0, "18" => 0, "19" => 0, "20" => 0,
               "21" => 0, "22" => 0, "23" => 0, "24" => 0,
             };
  
  for my $k (sort keys %{$data{$type}{$name}{nexthours}}) {
      my $nhtime = NexthoursVal ($hash, $k, "starttime", undef);                                      # Startzeit
      next if(!$nhtime);
      
      $dnum       = 0;
      $consumerco = 0;
      $min        =  (~0 >> 1);
      $max        = -(~0 >> 1);
      my $utime   = timestringToTimestamp ($nhtime);
      my $nhday   = strftime "%a", localtime($utime);                                               # Wochentagsname des NextHours Key
      my $nhhr    = sprintf("%02d", (int (strftime "%H", localtime($utime))) + 1);                  # Stunde des Tages vom NextHours Key  (01,02,...24) 
      
      for my $m (sort{$a<=>$b} keys %{$data{$type}{$name}{pvhist}}) {
          next if($m eq $day);                                                                      # next wenn gleicher Tag (Datum) wie heute
          
          if ($swdfcfc) {                                                                           # nur gleiche Tage (Mo...So) einbeziehen
              my $hdn = HistoryVal ($hash, $m, 99, "dayname", undef);
              next if(!$hdn || $hdn ne $nhday);
          }
          
          my $hcon = HistoryVal ($hash, $m, $nhhr, "con", 0);  
          next if(!$hcon);
          
          for my $c (sort{$a<=>$b} keys %{$acref}) {                                                # historischer Verbrauch aller registrierten Verbraucher aufaddieren
              $consumerco += HistoryVal ($hash, $m, $nhhr, "csme${c}", 0);
          }
          
          $hcon -= $consumerco if($hcon >= $consumerco);                                            # Verbrauch registrierter Verbraucher aus Verbrauch eliminieren
          
          $min = $hcon if($hcon < $min);
          $max = $hcon if($hcon > $max);
          
          $conh->{$nhhr} += $hcon;  
          $dnum++;
      }
      
      if ($dnum) {
           my $hdiff                                 = ($max - $min)/$dnum;                         # Glättungsdifferenz
           my $conavg                                = int(($conh->{$nhhr}/$dnum)-$hdiff);
           $data{$type}{$name}{nexthours}{$k}{confc} = $conavg;                                     # Durchschnittsverbrauch aller gleicher Wochentage pro Stunde
           
           if (NexthoursVal ($hash, $k, "today", 0)) {                                              # nur Werte des aktuellen Tag speichern
               $data{$type}{$name}{circular}{sprintf("%02d",$nhhr)}{confc} = $conavg; 
               
               $paref->{confc}    = $conavg;
               $paref->{nhour}    = sprintf("%02d",$nhhr);
               $paref->{histname} = "confc";
               setPVhistory ($paref);
               delete $paref->{histname};  
           }          
           
           Log3 ($name, 4, "$name - estimated Consumption for $nhday -> starttime: $nhtime, con: $conavg, days for avg: $dnum, hist. consumption registered consumers: ".sprintf "%.2f", $consumerco);
      }     
  }
  
return;
}

################################################################
#     Schwellenwerte auswerten und signalisieren
################################################################
sub _evaluateThresholds {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $daref = $paref->{daref};
   
  my $pt    = ReadingsVal($name, "powerTrigger", "");
  my $eh4t  = ReadingsVal($name, "energyH4Trigger", "");
  
  if ($pt) {  
      my $aaref = CurrentVal ($hash, "genslidereg", ""); 
      my @aa    = ();
      @aa       = @{$aaref} if (ref $aaref eq "ARRAY");
      
      if (scalar @aa >= $defslidenum) {  
          $paref->{taref}  = \@aa;
          $paref->{tname}  = "powerTrigger";
          $paref->{tholds} = $pt;
          
          __evaluateArray ($paref);
      }
  }
  
  if ($eh4t) {  
      my $aaref = CurrentVal ($hash, "h4fcslidereg", ""); 
      my @aa    = ();
      @aa       = @{$aaref} if (ref $aaref eq "ARRAY");
      
      if (scalar @aa >= $defslidenum) {    
          $paref->{taref}  = \@aa;
          $paref->{tname}  = "energyH4Trigger";
          $paref->{tholds} = $eh4t;
          
          __evaluateArray ($paref);
      }
  }
  
  delete $paref->{taref};
  delete $paref->{tname};
  delete $paref->{tholds};
  
return;
}

################################################################
#     Threshold-Array auswerten und Readings vorbereiten
################################################################
sub __evaluateArray {
  my $paref  = shift;
  my $name   = $paref->{name};
  my $daref  = $paref->{daref};
  my $taref  = $paref->{taref};          # Referenz zum Threshold-Array
  my $tname  = $paref->{tname};          # Thresholdname, z.B. powerTrigger
  my $tholds = $paref->{tholds};         # Triggervorgaben, z.B. aus Reading powerTrigger
      
  my $gen1   = @$taref[0];
  my $gen2   = @$taref[1];
  my $gen3   = @$taref[2];
  
  my ($a,$h) = parseParams ($tholds);
  
  for my $key (keys %{$h}) {
      my ($knum,$cond) = $key =~ /^([0-9]+)(on|off)$/x;
      
      if($cond eq "on" && $gen1 > $h->{$key}) {
          next if($gen2 < $h->{$key});
          next if($gen3 < $h->{$key});             
          push @$daref, "${tname}_${knum}<>on"  if(ReadingsVal($name, "${tname}_${knum}", "off") eq "off");
      }
      
      if($cond eq "off" && $gen1 < $h->{$key}) {
          next if($gen2 > $h->{$key});
          next if($gen3 > $h->{$key});
          push @$daref, "${tname}_${knum}<>off" if(ReadingsVal($name, "${tname}_${knum}", "on") eq "on");
      }
  }
  
return;
}

################################################################
#      zusätzliche Readings Tomorrow_HourXX_PVforecast
#      berechnen
################################################################
sub _calcReadingsTomorrowPVFc {  
  my $paref  = shift;
  my $hash   = $paref->{hash};
  my $name   = $paref->{name};
  my $daref  = $paref->{daref};
  
  my $type   = $hash->{TYPE};
  
  deleteReadingspec ($hash, "Tomorrow_Hour.*");
  
  my $h    = $data{$type}{$name}{nexthours};
  my $hods = AttrVal($name, 'createTomorrowPVFcReadings', '');
  return if(!keys %{$h} || !$hods);
  
  for my $idx (sort keys %{$h}) {
      my $today = NexthoursVal ($hash, $idx, 'today', 1);   
      next if($today);                                                             # aktueller Tag wird nicht benötigt 

      my $h  = NexthoursVal ($hash, $idx, 'hourofday', ''); 
      next if(!$h);

      next if($hods !~ /$h/xs);                                                    # diese Stunde des Tages soll nicht erzeugt werden 
      
      my $st = NexthoursVal ($hash, $idx, 'starttime', 'XXXX-XX-XX XX:XX:XX');     # Starttime
      
      my $pvfc = NexthoursVal ($hash, $idx, 'pvforecast', 0);
      
      push @$daref, "Tomorrow_Hour".$h."_PVforecast<>".$pvfc." Wh";
  }
    
return;
}

################################################################
#               Zusammenfassungen erstellen
################################################################
sub _calcSummaries {  
  my $paref  = shift;
  my $hash   = $paref->{hash};
  my $name   = $paref->{name};
  my $daref  = $paref->{daref};
  my $chour  = $paref->{chour};                                                                       # aktuelle Stunde
  my $minute = $paref->{minute};                                                                      # aktuelle Minute
  
  my $type   = $hash->{TYPE};
  $minute    = (int $minute) + 1;                                                                     # Minute Range umsetzen auf 1 bis 60
  
  ## Vorhersagen
  ################
  my $next1HoursSum = { "PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0 };
  my $next2HoursSum = { "PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0 };
  my $next3HoursSum = { "PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0 };
  my $next4HoursSum = { "PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0 };
  my $restOfDaySum  = { "PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0 };
  my $tomorrowSum   = { "PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0 };
  my $todaySum      = { "PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0 };
  
  my $rdh              = 24 - $chour - 1;                                                             # verbleibende Anzahl Stunden am Tag beginnend mit 00 (abzüglich aktuelle Stunde)
  my $remainminutes    = 60 - $minute;                                                                # verbleibende Minuten der aktuellen Stunde
  
  my $restofhourpvfc   = (NexthoursVal($hash, "NextHour00", "pvforecast", 0)) / 60 * $remainminutes;
  my $restofhourconfc  = (NexthoursVal($hash, "NextHour00", "confc",      0)) / 60 * $remainminutes;
  
  $next1HoursSum->{PV}          = $restofhourpvfc;
  $next2HoursSum->{PV}          = $restofhourpvfc;
  $next3HoursSum->{PV}          = $restofhourpvfc;
  $next4HoursSum->{PV}          = $restofhourpvfc;
  $restOfDaySum->{PV}           = $restofhourpvfc;
  
  $next1HoursSum->{Consumption} = $restofhourconfc;
  $next2HoursSum->{Consumption} = $restofhourconfc;
  $next3HoursSum->{Consumption} = $restofhourconfc;
  $next4HoursSum->{Consumption} = $restofhourconfc;
  $restOfDaySum->{Consumption}  = $restofhourconfc;
  
  for my $h (1..47) {
      my $pvfc  = NexthoursVal ($hash, "NextHour".sprintf("%02d",$h), "pvforecast", 0);
      my $confc = NexthoursVal ($hash, "NextHour".sprintf("%02d",$h), "confc",      0);
         
      if($h == 1) {
          $next1HoursSum->{PV}          += $pvfc  / 60 * $minute;
          $next1HoursSum->{Consumption} += $confc / 60 * $minute;
      }
      
      if($h <= 2) {
          $next2HoursSum->{PV}          += $pvfc                 if($h <  2);
          $next2HoursSum->{PV}          += $pvfc  / 60 * $minute if($h == 2);
          $next2HoursSum->{Consumption} += $confc                if($h <  2);
          $next2HoursSum->{Consumption} += $confc / 60 * $minute if($h == 2); 
      }
      
      if($h <= 3) {
          $next3HoursSum->{PV}          += $pvfc                 if($h <  3);
          $next3HoursSum->{PV}          += $pvfc  / 60 * $minute if($h == 3); 
          $next3HoursSum->{Consumption} += $confc                if($h <  3);
          $next3HoursSum->{Consumption} += $confc / 60 * $minute if($h == 3); 
      }  

      if($h <= 4) {
          $next4HoursSum->{PV}          += $pvfc                 if($h <  4);
          $next4HoursSum->{PV}          += $pvfc  / 60 * $minute if($h == 4); 
          $next4HoursSum->{Consumption} += $confc                if($h <  4);
          $next4HoursSum->{Consumption} += $confc / 60 * $minute if($h == 4);
      }      
      
      $restOfDaySum->{PV}          += $pvfc  if($h <= $rdh);
      $restOfDaySum->{Consumption} += $confc if($h <= $rdh);
      
      $tomorrowSum->{PV}           += $pvfc if($h >  $rdh);
  }
  
  for my $th (1..24) {
      $todaySum->{PV} += ReadingsNum($name, "Today_Hour".sprintf("%02d",$th)."_PVforecast", 0);
  }
  
  push @{$data{$type}{$name}{current}{h4fcslidereg}}, int $next4HoursSum->{PV};                         # Schieberegister 4h Summe Forecast
  limitArray ($data{$type}{$name}{current}{h4fcslidereg}, $defslidenum);
  
  my $gcon    = CurrentVal ($hash, "gridconsumption",     0);                                           # aktueller Netzbezug
  my $tconsum = CurrentVal ($hash, "tomorrowconsumption", undef);                                       # Verbrauchsprognose für folgenden Tag
  my $pvgen   = CurrentVal ($hash, "generation",          0);
  my $gfeedin = CurrentVal ($hash, "gridfeedin",          0);
  my $batin   = CurrentVal ($hash, "powerbatin",          0);                                           # aktuelle Batterieladung
  my $batout  = CurrentVal ($hash, "powerbatout",         0);                                           # aktuelle Batterieentladung
  
  my $consumption         = int ($pvgen - $gfeedin + $gcon - $batin + $batout);
  my $selfconsumption     = int ($pvgen - $gfeedin - $batin + $batout);
  $selfconsumption        = $selfconsumption < 0 ? 0 : $selfconsumption;
  my $surplus             = int ($pvgen - $consumption);                                                # aktueller Überschuß
  my $selfconsumptionrate = 0;
  my $autarkyrate         = 0;
  $selfconsumptionrate    = sprintf("%.0f", $selfconsumption / $pvgen * 100) if($pvgen * 1 > 0);
  $autarkyrate            = sprintf("%.0f", $selfconsumption / ($selfconsumption + $gcon) * 100) if($selfconsumption);
  
  $data{$type}{$name}{current}{consumption}         = $consumption;
  $data{$type}{$name}{current}{selfconsumption}     = $selfconsumption;
  $data{$type}{$name}{current}{selfconsumptionrate} = $selfconsumptionrate;
  $data{$type}{$name}{current}{autarkyrate}         = $autarkyrate;
  $data{$type}{$name}{current}{surplus}             = $surplus;
  
  push @$daref, "Current_Consumption<>".         $consumption.              " W";
  push @$daref, "Current_SelfConsumption<>".     $selfconsumption.          " W";
  push @$daref, "Current_SelfConsumptionRate<>". $selfconsumptionrate.      " %";
  push @$daref, "Current_AutarkyRate<>".         $autarkyrate.              " %";
  
  push @$daref, "NextHours_Sum01_PVforecast<>".  (int $next1HoursSum->{PV})." Wh";
  push @$daref, "NextHours_Sum02_PVforecast<>".  (int $next2HoursSum->{PV})." Wh";
  push @$daref, "NextHours_Sum03_PVforecast<>".  (int $next3HoursSum->{PV})." Wh";
  push @$daref, "NextHours_Sum04_PVforecast<>".  (int $next4HoursSum->{PV})." Wh";
  push @$daref, "RestOfDayPVforecast<>".         (int $restOfDaySum->{PV}). " Wh";
  push @$daref, "Tomorrow_PVforecast<>".         (int $tomorrowSum->{PV}).  " Wh";
  push @$daref, "Today_PVforecast<>".            (int $todaySum->{PV}).     " Wh";
  
  push @$daref, "Tomorrow_ConsumptionForecast<>".           $tconsum.                          " Wh" if(defined $tconsum);
  push @$daref, "NextHours_Sum04_ConsumptionForecast<>".   (int $next4HoursSum->{Consumption})." Wh";
  push @$daref, "RestOfDayConsumptionForecast<>".          (int $restOfDaySum->{Consumption}). " Wh";
  
return;
}

################################################################
#     Berechnen Forecast Tag / Stunden Verschieber
#     aus aktueller Stunde + lfd. Nummer
################################################################
sub _calcDayHourMove {               
  my $chour = shift;
  my $num   = shift;

  my $fh = $chour + $num; 
  my $fd = int ($fh / 24) ;
  $fh    = $fh - ($fd * 24);  
   
return ($fd,$fh);
}

################################################################
#    Spezialfall auflösen wenn Wert von $val2 dem 
#    Redingwert von $val1 entspricht sofern $val1 negativ ist
################################################################
sub substSpecialCases {
  my $paref = shift; 
  my $dev   = $paref->{dev};
  my $rdg   = $paref->{rdg};
  my $rdgf  = $paref->{rdgf};

  my $val1  = ReadingsNum ($dev, $rdg, 0) * $rdgf;
  my $val2;
  
  if($val1 <= 0) {
      $val2 = abs($val1);
      $val1 = 0;
  }
  else {
      $val2 = 0;
  }
 
return ($val1,$val2);
}

################################################################
#     Energieverbrauch des Hauses in History speichern
################################################################
sub saveEnergyConsumption {
  my $paref = shift;
  my $name  = $paref->{name};
  my $chour = $paref->{chour};  
  
  my $pvrl    = ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour+1)."_PVreal",          0);
  my $gfeedin = ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour+1)."_GridFeedIn",      0);
  my $gcon    = ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour+1)."_GridConsumption", 0);
  my $batin   = ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour+1)."_BatIn",           0);
  my $batout  = ReadingsNum($name, "Today_Hour".sprintf("%02d",$chour+1)."_BatOut",          0);
  
  my $con = $pvrl - $gfeedin + $gcon - $batin + $batout;
      
  $paref->{con}      = $con;
  $paref->{nhour}    = sprintf("%02d",$chour+1);
  $paref->{histname} = "con";
  setPVhistory ($paref);              
  delete $paref->{histname};
   
return;
}

################################################################
#         Grunddaten aller registrierten Consumer speichern
################################################################
sub collectAllRegConsumers {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name}; 
  
  my $type  = $hash->{TYPE};
              
  delete $data{$type}{$name}{current}{consumerdevs};
  
  for my $c (1..$maxconsumer) {
      $c           = sprintf "%02d", $c;
      my $consumer = AttrVal ($name, "consumer${c}", "");
      next if(!$consumer);
      
      my ($ac,$hc) = parseParams ($consumer);
      $consumer    = $ac->[0] // "";
      
      if(!$consumer || !$defs{$consumer}) {
          my $err = qq{ERROR - the device "$consumer" doesn't exist anymore! Delete or change the attribute "consumer${c}".};
          Log3 ($name, 1, "$name - $err");
          next; 
      }
      
      push @{$data{$type}{$name}{current}{consumerdevs}}, $consumer;                              # alle Consumerdevices in CurrentHash eintragen
      
      my $alias = AttrVal ($consumer, "alias", $consumer);
      
      my ($rtot,$utot,$ethreshold);
      if(exists $hc->{etotal}) {
          my $etotal                = $hc->{etotal};
          ($rtot,$utot,$ethreshold) = split ":", $etotal;
      }
      
      my ($rpcurr,$upcurr,$pthreshold);
      if(exists $hc->{pcurr}) {       
          my $pcurr                     = $hc->{pcurr};
          ($rpcurr,$upcurr,$pthreshold) = split ":", $pcurr;
      }
      
      my ($rswstate,$onreg,$offreg);
      if(exists $hc->{swstate}) {
          ($rswstate,$onreg,$offreg) = split ":", $hc->{swstate};
      }
      
      my ($dswoncond,$rswoncond,$swoncondregex);
      if(exists $hc->{swoncond}) {                                                                # zusätzliche Einschaltbedingung
          ($dswoncond,$rswoncond,$swoncondregex) = split ":", $hc->{swoncond};
      } 

      my ($dswoffcond,$rswoffcond,$swoffcondregex);
      if(exists $hc->{swoffcond}) {                                                               # vorrangige Ausschaltbedingung
          ($dswoffcond,$rswoffcond,$swoffcondregex) = split ":", $hc->{swoffcond};
      }

      my $interruptable = 0;
      if(exists $hc->{interruptable}) {
          $interruptable = 1 if($hc->{interruptable} ne '0');
      }      
      
      my $rauto     = $hc->{auto}     // q{};
      my $ctype     = $hc->{type}     // $defctype;
      my $auto      = 1;
      $auto         = ReadingsVal ($consumer, $rauto, 1) if($rauto);                               # Reading für Ready-Bit -> Einschalten möglich ?

      $data{$type}{$name}{consumers}{$c}{name}            = $consumer;                             # Name des Verbrauchers (Device)
      $data{$type}{$name}{consumers}{$c}{alias}           = $alias;                                # Alias des Verbrauchers (Device)
      $data{$type}{$name}{consumers}{$c}{type}            = $hc->{type}      // $defctype;         # Typ des Verbrauchers
      $data{$type}{$name}{consumers}{$c}{power}           = $hc->{power};                          # Leistungsaufnahme des Verbrauchers in W
      $data{$type}{$name}{consumers}{$c}{avgenergy}       = q{};                                   # Initialwert Energieverbrauch (evtl. Überschreiben in manageConsumerData)
      $data{$type}{$name}{consumers}{$c}{mintime}         = $hc->{mintime}   // $hef{$ctype}{mt};  # Initialwert min. Einschalt- bzw. Zykluszeit (evtl. Überschreiben in manageConsumerData)
      $data{$type}{$name}{consumers}{$c}{mode}            = $hc->{mode}      // $defcmode;         # Planungsmode des Verbrauchers
      $data{$type}{$name}{consumers}{$c}{icon}            = $hc->{icon}      // q{};               # Icon für den Verbraucher
      $data{$type}{$name}{consumers}{$c}{oncom}           = $hc->{on}        // q{};               # Setter Einschaltkommando 
      $data{$type}{$name}{consumers}{$c}{offcom}          = $hc->{off}       // q{};               # Setter Ausschaltkommando
      $data{$type}{$name}{consumers}{$c}{autoreading}     = $rauto;                                # Readingname zur Automatiksteuerung
      $data{$type}{$name}{consumers}{$c}{auto}            = $auto;                                 # Automaticsteuerung: 1 - Automatic ein, 0 - Automatic aus 
      $data{$type}{$name}{consumers}{$c}{retotal}         = $rtot            // q{};               # Reading der Leistungsmessung
      $data{$type}{$name}{consumers}{$c}{uetotal}         = $utot            // q{};               # Unit der Leistungsmessung
      $data{$type}{$name}{consumers}{$c}{energythreshold} = $ethreshold      // 0;                 # Schwellenwert (Wh pro Stunde) ab der ein Verbraucher als aktiv gewertet wird  
      $data{$type}{$name}{consumers}{$c}{rpcurr}          = $rpcurr          // q{};               # Reading der aktuellen Leistungsaufnahme
      $data{$type}{$name}{consumers}{$c}{upcurr}          = $upcurr          // q{};               # Unit der aktuellen Leistungsaufnahme
      $data{$type}{$name}{consumers}{$c}{powerthreshold}  = $pthreshold      // 0;                 # Schwellenwert d. aktuellen Leistung(W) ab der ein Verbraucher als aktiv gewertet wird  
      $data{$type}{$name}{consumers}{$c}{notbefore}       = $hc->{notbefore} // q{};               # nicht einschalten vor Stunde in 24h Format (00-23)
      $data{$type}{$name}{consumers}{$c}{notafter}        = $hc->{notafter}  // q{};               # nicht einschalten nach Stunde in 24h Format (00-23)
      $data{$type}{$name}{consumers}{$c}{rswstate}        = $rswstate        // 'state';           # Schaltstatus Reading
      $data{$type}{$name}{consumers}{$c}{onreg}           = $onreg           // 'on';              # Regex für 'ein'
      $data{$type}{$name}{consumers}{$c}{offreg}          = $offreg          // 'off';             # Regex für 'aus'
      $data{$type}{$name}{consumers}{$c}{dswoncond}       = $dswoncond       // q{};               # Device zur Lieferung einer zusätzliche Einschaltbedingung
      $data{$type}{$name}{consumers}{$c}{rswoncond}       = $rswoncond       // q{};               # Reading zur Lieferung einer zusätzliche Einschaltbedingung
      $data{$type}{$name}{consumers}{$c}{swoncondregex}   = $swoncondregex   // q{};               # Regex einer zusätzliche Einschaltbedingung
      $data{$type}{$name}{consumers}{$c}{dswoffcond}      = $dswoffcond      // q{};               # Device zur Lieferung einer vorrangigen Ausschaltbedingung
      $data{$type}{$name}{consumers}{$c}{rswoffcond}      = $rswoffcond      // q{};               # Reading zur Lieferung einer vorrangigen Ausschaltbedingung
      $data{$type}{$name}{consumers}{$c}{swoffcondregex}  = $swoffcondregex  // q{};               # Regex einer vorrangigen Ausschaltbedingung
      $data{$type}{$name}{consumers}{$c}{interruptable}   = $interruptable;                        # Ein-Zustand des Verbrauchers ist unterbrechbar
  }
  
  Log3 ($name, 5, "$name - all registered consumers:\n".Dumper $data{$type}{$name}{consumers});
    
return;
}

################################################################
#              FHEMWEB Fn
################################################################
sub FwFn {
  my ($FW_wname, $name, $room, $pageHash) = @_;                                  # pageHash is set for summaryFn.
  my $hash = $defs{$name};
  
  RemoveInternalTimer($hash, \&pageRefresh);
  $hash->{HELPER}{FW} = $FW_wname;
  
  my $ret = entryGraphic ($name);
  
  # Autorefresh nur des aufrufenden FHEMWEB-Devices
  my $al = AttrVal($name, "autoRefresh", 0);
  if($al) {  
      InternalTimer(gettimeofday()+$al, \&pageRefresh, $hash, 0);
      Log3 ($name, 5, "$name - next start of autoRefresh: ".FmtDateTime(gettimeofday()+$al));
  }

return $ret;
}

################################################################
sub pageRefresh { 
  my $hash = shift;
  my $name = $hash->{NAME};
  
  # Seitenrefresh festgelegt durch SolarForecast-Attribut "autoRefresh" und "autoRefreshFW"
  my $rd = AttrVal($name, "autoRefreshFW", $hash->{HELPER}{FW});
  { map { FW_directNotify("#FHEMWEB:$_", "location.reload('true')", "") } $rd }       ## no critic 'Map blocks'
  
  my $al = AttrVal($name, "autoRefresh", 0);
  
  if($al) {      
      InternalTimer(gettimeofday()+$al, \&pageRefresh, $hash, 0);
      Log3 ($name, 5, "$name - next start of autoRefresh: ".FmtDateTime(gettimeofday()+$al));
  } 
  else {
      RemoveInternalTimer($hash, \&pageRefresh);
  }
  
return;
}

################################################################
#    Grafik als HTML zurück liefern    (z.B. für Widget)
################################################################
sub pageAsHtml { 
  my $hash = shift;
  my $ftui = shift;
  my $name = $hash->{NAME};
  
  my $ret = "<html>";
  $ret   .= entryGraphic ($name);
  $ret   .= "</html>";
  
return $ret;
}

################################################################
#                  Einstieg Grafikanzeige
################################################################
sub entryGraphic {                                
  my $name = shift;
  my $ftui = shift // "";
  
  my $hash = $defs{$name};
  
  # Setup Vollständigkeit prüfen
  ###############################
  my $incomplete = _checkSetupComplete ($hash);
  return $incomplete if($incomplete);
  
  # Kontext des SolarForecast-Devices speichern für Refresh
  ##########################################################
  $hash->{HELPER}{SPGDEV}    = $name;                                                      # Name des aufrufenden SolarForecastSPG-Devices
  $hash->{HELPER}{SPGROOM}   = $FW_room   ? $FW_room   : "";                               # Raum aus dem das SolarForecastSPG-Device die Funktion aufrief
  $hash->{HELPER}{SPGDETAIL} = $FW_detail ? $FW_detail : "";                               # Name des SolarForecastSPG-Devices (wenn Detailansicht)

  # Parameter f. Anzeige extrahieren
  ###################################   
  my $width      = AttrNum ($name, 'beamWidth',           6);                              # zu klein ist nicht problematisch  
  my $maxhours   = AttrNum ($name, 'hourCount',          24);
  my $colorw     = AttrVal ($name, 'weatherColor', 'FFFFFF');                              # Wetter Icon Farbe
  
  my $alias      = AttrVal ($name, "alias", $name);                                        # Linktext als Aliasname oder Devicename setzen
  my $gsel       = AttrVal ($name, 'graphicSelect', 'both');                               # Auswahl der anzuzeigenden Grafiken
  my $dlink      = qq{<a href="$FW_ME$FW_subdir?detail=$name">$alias</a>}; 

  my $html_start = AttrVal ($name, 'htmlStart', undef);                                    # beliebige HTML Strings die vor der Grafik ausgegeben werden
  my $html_end   = AttrVal ($name, 'htmlEnd',   undef);                                    # beliebige HTML Strings die nach der Grafik ausgegeben werden
  my $w          = $width * $maxhours;                                                     # gesammte Breite der Ausgabe , WetterIcon braucht ca. 34px
  
  my $paref = {
      hash           => $hash,
      name           => $name,
      ftui           => $ftui,
      maxhours       => $maxhours,
      modulo         => 1,
      dstyle         => qq{style='padding-left: 10px; padding-right: 10px; padding-top: 3px; padding-bottom: 3px;'},     # TD-Style
      offset         => AttrNum ($name,    'historyHour',                       0),
      hourstyle      => AttrVal ($name,    'hourStyle',                        ''),
      colorfc        => AttrVal ($name,    'beam1Color',                 '000000'),
      colorc         => AttrVal ($name,    'beam2Color',                 'C4C4A7'),
      fcolor1        => AttrVal ($name,    'beam1FontColor',             'C4C4A7'),
      fcolor2        => AttrVal ($name,    'beam2FontColor',             '000000'),  
      beam1cont      => AttrVal ($name,    'beam1Content',           'pvForecast'),
      beam2cont      => AttrVal ($name,    'beam2Content',           'pvForecast'), 
      caicon         => AttrVal ($name,    'consumerAdviceIcon',       $caicondef),            # Consumer AdviceIcon
      clegend        => AttrVal ($name,    'consumerLegend',           'icon_top'),            # Lage und Art Cunsumer Legende
      lotype         => AttrVal ($name,    'layoutType',                 'single'),
      kw             => AttrVal ($name,    'Wh/kWh',                         'Wh'),
      height         => AttrNum ($name,    'beamHeight',                      200),
      width          => $width,
      fsize          => AttrNum ($name,    'spaceSize',                        24),
      maxVal         => AttrNum ($name,    'maxValBeam',                        0),            # dyn. Anpassung der Balkenhöhe oder statisch ?
      show_night     => AttrNum ($name,    'showNight',                         0),            # alle Balken (Spalten) anzeigen ?
      show_diff      => AttrVal ($name,    'showDiff',                       'no'),            # zusätzliche Anzeige $di{} in allen Typen
      weather        => AttrNum ($name,    'showWeather',                       1),
      colorw         => $colorw,
      colorwn        => AttrVal ($name,    'weatherColorNight',           $colorw),            # Wetter Icon Farbe Nacht
      wlalias        => AttrVal ($name,    'alias',                         $name),
      header         => AttrNum ($name,    'showHeader',                        1), 
      hdrDetail      => AttrVal ($name,    'headerDetail',                  'all'),            # ermöglicht den Inhalt zu begrenzen, um bspw. passgenau in ftui einzubetten
      lang           => AttrVal ("global", 'language',                       'EN'),
      flowgh         => AttrVal ($name,    'flowGraphicSize',       $defflowGSize),            # Größe Energieflußgrafik
      flowgani       => AttrVal ($name,    'flowGraphicAnimate',                0),            # Animation Energieflußgrafik
      flowgcons      => AttrVal ($name,    'flowGraphicShowConsumer',           1),            # Verbraucher in der Energieflußgrafik anzeigen
      flowgconX      => AttrVal ($name,    'flowGraphicShowConsumerDummy',      1),            # Dummyverbraucher in der Energieflußgrafik anzeigen                                                                                                                                         
      flowgconsPower => AttrVal ($name,    'flowGraphicShowConsumerPower'     , 1),            # Verbraucher Leistung in der Energieflußgrafik anzeigen
      flowgconsTime  => AttrVal ($name,    'flowGraphicShowConsumerRemainTime', 1),            # Verbraucher Restlaufeit in der Energieflußgrafik anzeigen                                                                                                                                                         
      flowgconsDist  => AttrVal ($name,    'flowGraphicConsumerDistance',      80),            # Abstand Verbrauchericons zueinander
      css            => AttrVal ($name,    'Css',                         $cssdef),            # Css Styles
  };
  
  my $ret = q{};
  
  if(IsDisabled($name)) {   
      $ret .= "<table class='roomoverview'>";
      $ret .= "<tr style='height:".$paref->{height}."px'>";
      $ret .= "<td>";
      $ret .= qq{SolarForecast device <a href="$FW_ME$FW_subdir?detail=$name">$name</a> is disabled}; 
      $ret .= "</td>";
      $ret .= "</tr>";
      $ret .= "</table>";
  } 
  else {
      $ret .= "<span>$dlink </span><br>"  if(AttrVal($name,"showLink",0));
      
      $ret .= "<html>";
      $ret .= $html_start if (defined($html_start));
      $ret .= "<style>TD.solarfc {text-align: center; padding-left:1px; padding-right:1px; margin:0px;}</style>";
      $ret .= "<table class='roomoverview' width='$w' style='width:".$w."px'><tr class='devTypeTr'></tr>";
      $ret .= "<tr><td class='solarfc'>";
      
      # Headerzeile generieren 
      ##########################  
      my $header       = _graphicHeader ($paref);
      $paref->{header} = $header;
      
      # Verbraucherlegende und Steuerung
      ###################################           
      my $legendtxt       = _graphicConsumerLegend ($paref);
      $paref->{legendtxt} = $legendtxt;
      
      $ret .= "\n<table class='block'>";                                                                        # das \n erleichtert das Lesen der debug Quelltextausgabe
      my $m = $paref->{modulo} % 2;
      
      if ($header) {                                                                                            # Header ausgeben 
          $ret .= "<tr class='$htr{$m}{cl}'>";                                                                  
          $ret .= "<td colspan='".($maxhours+2)."' align='center' style='word-break: normal'>$header</td>";
          $ret .= "</tr>";
          
          $paref->{modulo}++;
      }
      
      my $clegend = $paref->{clegend};
      $m          = $paref->{modulo} % 2;
      
      if ($legendtxt && ($clegend eq 'top')) {
          $ret .= "<tr class='$htr{$m}{cl}'>";
          $ret .= "<td colspan='".($maxhours+2)."' align='center' style='word-break: normal'>$legendtxt</td>";
          $ret .= "</tr>";
          
          $paref->{modulo}++;
      }
      
      $m = $paref->{modulo} % 2;
                  
      if($gsel eq "both" || $gsel eq "forecast") {
          my %hfch;
          my $hfcg  = \%hfch;                                                                                   #(hfcg = hash forecast graphic)
          
          # Werte aktuelle Stunde
          ########################## 
          $paref->{hfcg}     = $hfcg;
          $paref->{thishour} = _beamGraphicFirstHour ($paref);

          # get consumer list and display it in Graphics
          ################################################ 
          _showConsumerInGraphicBeam ($paref);

          # Werte restliche Stunden
          ###########################
          my $back         = _beamGraphicRemainingHours ($paref);
          $paref->{maxVal} = $back->{maxVal};                                                                  # Startwert wenn kein Wert bereits via attr vorgegeben ist
          $paref->{maxCon} = $back->{maxCon};                                                                       
          $paref->{maxDif} = $back->{maxDif};                                                                  # für Typ diff
          $paref->{minDif} = $back->{minDif};                                                                  # für Typ diff

          #Log3 ($hash,3,Dumper($hfcg));
          
          # Balkengrafik
          ################
          $ret .= _beamGraphic ($paref);   
      }
      
      $m = $paref->{modulo} % 2;
      
      if($gsel eq "both" || $gsel eq "flow") {
          $ret  .= "<tr class='$htr{$m}{cl}'>";
          my $fg = _flowGraphic ($paref);
          $ret  .= "<td colspan='".($maxhours+2)."' align='center' style='word-break: normal'>$fg</td>";
          $ret  .= "</tr>";
          
          $paref->{modulo}++;
      }
      
      $m = $paref->{modulo} % 2;
      
      # Legende unten
      #################
      if ($legendtxt && ($clegend eq 'bottom')) {
          $ret .= "<tr class='$htr{$m}{cl}'>";
          $ret .= "<td colspan='".($maxhours+2)."' align='center' style='word-break: normal'>";
          $ret .= "$legendtxt</td></tr>";
      }
      
      $ret .= "</table>";
      
      $ret .= "</td></tr>";
      $ret .= "</table>";
      $ret .= $html_end if (defined($html_end));
      $ret .= "</html>";
  }
 
return $ret;
}

################################################################
#       Vollständigkeit Setup prüfen
################################################################
sub _checkSetupComplete {                                
  my $hash  = shift;
  my $ret   = q{};
  my $name  = $hash->{NAME};
  
  my $is    = ReadingsVal  ($name, "inverterStrings",          undef);                    # String Konfig
  my $fcdev = ReadingsVal  ($name, "currentForecastDev",       undef);                    # Forecast Device (Wetter)
  my $radev = ReadingsVal  ($name, "currentRadiationDev",      undef);                    # Forecast Device (Wetter) 
  my $indev = ReadingsVal  ($name, "currentInverterDev",       undef);                    # Inverter Device
  my $medev = ReadingsVal  ($name, "currentMeterDev",          undef);                    # Meter Device
  my $peak  = ReadingsVal  ($name, "modulePeakString",         undef);                    # String Peak
  my $pv0   = NexthoursVal ($hash, "NextHour00", "pvforecast", undef);
  my $dir   = ReadingsVal  ($name, "moduleDirection",          undef);                    # Modulausrichtung Konfig
  my $ta    = ReadingsVal  ($name, "moduleTiltAngle",          undef);                    # Modul Neigungswinkel Konfig
  
  if(!$is || !$fcdev || !$radev || !$indev || !$medev || !$peak || !defined $pv0 || !$dir || !$ta) {
      my $link   = qq{<a href="$FW_ME$FW_subdir?detail=$name">$name</a>};  
      my $height = AttrNum ($name,    'beamHeight',  200);
      my $lang   = AttrVal ("global", "language",   "EN");      
      
      $ret    .= "<table class='roomoverview'>";
      $ret    .= "<tr style='height:".$height."px'>";
      $ret    .= "<td>";
      
      if(!$fcdev) {                                                                        ## no critic 'Cascading'
          $ret .= $hqtxt{cfd}{$lang};
      }
      elsif(!$radev) {
          $ret .= $hqtxt{crd}{$lang};   
      }
      elsif(!$indev) {
          $ret .= $hqtxt{cid}{$lang}; 
      }
      elsif(!$medev) {
          $ret .= $hqtxt{mid}{$lang}; 
      }
      elsif(!$is) {
          $ret .= $hqtxt{ist}{$lang}; 
      }
      elsif(!$peak) {
          $ret .= $hqtxt{mps}{$lang};  
      }
      elsif(!$dir) {
          $ret .= $hqtxt{mdr}{$lang};
      }
      elsif(!$ta) {
          $ret .= $hqtxt{mta}{$lang};  
      }
      elsif(!defined $pv0) {
          $ret .= $hqtxt{awd}{$lang};   
      }
      
      $ret   .= "</td>";
      $ret   .= "</tr>";
      $ret   .= "</table>";
      $ret    =~ s/LINK/$link/gxs;
      return $ret;
  }
  
return;
}

################################################################
#         forecastGraphic Headerzeile generieren 
################################################################
sub _graphicHeader {                                
  my $paref  = shift;
  my $header = $paref->{header};
  
  return if(!$header);
  
  my $hdrDetail = $paref->{hdrDetail};                     # ermöglicht den Inhalt zu begrenzen, um bspw. passgenau in ftui einzubetten
  my $ftui      = $paref->{ftui};
  my $lang      = $paref->{lang};
  my $name      = $paref->{name};
  my $hash      = $paref->{hash};
  my $kw        = $paref->{kw};
  my $dstyle    = $paref->{dstyle};                        # TD-Style
       
  my $lup       = ReadingsTimestamp ($name, ".lastupdateForecastValues", "0000-00-00 00:00:00");   # letzter Forecast Update
 
  my $pcfa      = ReadingsVal ($name,"pvCorrectionFactor_Auto",         "off");
  my $co4h      = ReadingsNum ($name,"NextHours_Sum04_ConsumptionForecast", 0);
  my $coRe      = ReadingsNum ($name,"RestOfDayConsumptionForecast",        0); 
  my $coTo      = ReadingsNum ($name,"Tomorrow_ConsumptionForecast",        0);
  my $coCu      = ReadingsNum ($name,"Current_Consumption",                 0);
  my $pv4h      = ReadingsNum ($name,"NextHours_Sum04_PVforecast",          0);
  my $pvRe      = ReadingsNum ($name,"RestOfDayPVforecast",                 0); 
  my $pvTo      = ReadingsNum ($name,"Tomorrow_PVforecast",                 0);
  my $pvCu      = ReadingsNum ($name,"Current_PV",                          0);
  
  my $pvcorrf00  = NexthoursVal($hash, "NextHour00", "pvcorrf", "-/m");
  my ($pcf,$pcq) = split "/", $pvcorrf00;
  my $pvcanz     = "factor: $pcf / quality: $pcq";
  $pcq           =~ s/m/-1/xs;
  my $pvfc00     =  NexthoursVal($hash, "NextHour00", "pvforecast", undef);

  if ($kw eq 'kWh') {
      $co4h = sprintf("%.1f" , $co4h/1000)."&nbsp;kWh";
      $coRe = sprintf("%.1f" , $coRe/1000)."&nbsp;kWh";
      $coTo = sprintf("%.1f" , $coTo/1000)."&nbsp;kWh";
      $coCu = sprintf("%.1f" , $coCu/1000)."&nbsp;kW";
      $pv4h = sprintf("%.1f" , $pv4h/1000)."&nbsp;kWh";
      $pvRe = sprintf("%.1f" , $pvRe/1000)."&nbsp;kWh";
      $pvTo = sprintf("%.1f" , $pvTo/1000)."&nbsp;kWh";
      $pvCu = sprintf("%.1f" , $pvCu/1000)."&nbsp;kW";
  } 
  else {
      $co4h .= "&nbsp;Wh";
      $coRe .= "&nbsp;Wh";
      $coTo .= "&nbsp;Wh";
      $coCu .= "&nbsp;W";
      $pv4h .= "&nbsp;Wh";
      $pvRe .= "&nbsp;Wh";
      $pvTo .= "&nbsp;Wh";
      $pvCu .= "&nbsp;W";
  }
  
  my $lupt    = "last&nbsp;update:";
  my $autoct  = "automatic&nbsp;correction:";
  my $lbpcq   = "correction&nbsp;quality&nbsp;current&nbsp;hour:";      
  my $lblPv4h = "next&nbsp;4h:";
  my $lblPvRe = "remain&nbsp;today:";
  my $lblPvTo = "tomorrow:";
  my $lblPvCu = "actual:";
 
  if($lang eq "DE") {                                                                           # Header globales Sprachschema Deutsch
      $lupt    = "Stand:";
      $autoct  = "automatische&nbsp;Korrektur:";
      $lbpcq   = encode("utf8", "Korrekturqualität&nbsp;akt.&nbsp;Stunde:");          
      $lblPv4h = encode("utf8", "nächste&nbsp;4h:");
      $lblPvRe = "Rest&nbsp;heute:";
      $lblPvTo = "morgen:";
      $lblPvCu = "aktuell:";
  }
  
  ## Header Start
  #################
  $header = qq{<table width='100%'>}; 

  # Header Link + Status + Update Button     
  #########################################      
  if($hdrDetail eq "all" || $hdrDetail eq "statusLink") {
      my ($year, $month, $day, $time) = $lup =~ /(\d{4})-(\d{2})-(\d{2})\s+(.*)/x;
      
      $lup = "$year-$month-$day&nbsp;$time";
      if($lang eq "DE") {
         $lup = "$day.$month.$year&nbsp;$time"; 
      }

      my $cmdupdate = qq{"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=get $name data')"};               # Update Button generieren        

      if ($ftui eq "ftui") {
          $cmdupdate = qq{"ftui.setFhemStatus('get $name data')"};     
      }

      my $upstate = ReadingsVal($name, "state", "");

      ## Update-Icon
      ##############
      my ($upicon,$img);
      if ($upstate =~ /updated|successfully|switched/ix) {
          $img    = FW_makeImage('10px-kreis-gruen.png', $htitles{upd}{$lang});
          $upicon = "<a onClick=$cmdupdate>$img</a>";
      } 
      elsif ($upstate =~ /running/ix) {
          $img    = FW_makeImage('10px-kreis-gelb.png', 'running');
          $upicon = "<a>$img</a>";
      } 
      elsif ($upstate =~ /initialized/ix) {
          $img    = FW_makeImage('1px-spacer.png', 'initialized');
          $upicon = "<a>$img</a>";
      } 
      else {
          $img    = FW_makeImage('10px-kreis-rot.png', $htitles{upd}{$lang});
          $upicon = "<a onClick=$cmdupdate>$img</a>";
      }

      ## Autokorrektur-Icon
      ######################
      my $acicon;
      if ($pcfa eq "on") {
          $acicon = FW_makeImage('10px-kreis-gruen.png', $htitles{on}{$lang});
      } 
      elsif ($pcfa eq "off") {
          $htitles{akorron}{$lang} =~ s/<NAME>/$name/xs;
          $acicon = "<a title='$htitles{akorron}{$lang}'</a>off";         
      } 
      elsif ($pcfa =~ /standby/ix) {
          my ($rtime) = $pcfa =~ /for (.*?) hours/x;
          $img        = FW_makeImage('10px-kreis-gelb.png', $htitles{dela}{$lang});
          $acicon     = "$img&nbsp;(Start in ".$rtime." h)";
      } 
      else {
          $acicon = FW_makeImage('10px-kreis-rot.png', $htitles{undef}{$lang});
      }
      
      ## Qualitäts-Icon
      ######################
      my $pcqicon;
      
      $pcqicon = $pcq < 3 ? FW_makeImage('10px-kreis-rot.png',  $pvcanz) :  
                 $pcq < 5 ? FW_makeImage('10px-kreis-gelb.png', $pvcanz) :  
                 FW_makeImage('10px-kreis-gruen.png', $pvcanz);
      
      $pcqicon = "-" if(!$pvfc00 || $pcq == -1);

      ## erste Header-Zeilen
      #######################
      my $alias = AttrVal ($name, "alias", $name );                                               # Linktext als Aliasname
      my $dlink = qq{<a href="$FW_ME$FW_subdir?detail=$name">$alias</a>}; 
 
      $header  .= qq{<tr><td colspan="3" align="left" $dstyle><b> $dlink </b></td><td colspan="3" align="left" $dstyle> $lupt   &nbsp; $lup &nbsp; $upicon </td><td>                                                         </td></tr>};
      $header  .= qq{<tr><td colspan="3" align="left" $dstyle><b>        </b></td><td colspan="3" align="left" $dstyle> $autoct &nbsp;             $acicon </td><td colspan="3" align="left" $dstyle> $lbpcq &nbsp; $pcqicon </td></tr>};
  }
  
  # Header Information pv 
  ########################
  if($hdrDetail eq "all" || $hdrDetail eq "pv" || $hdrDetail eq "pvco") {   
      $header .= "<tr>";
      $header .= "<td $dstyle><b>PV&nbsp;=></b></td>";
      $header .= "<td $dstyle><b>$lblPvCu</b></td> <td align=right $dstyle>$pvCu</td>";
      $header .= "<td $dstyle><b>$lblPv4h</b></td> <td align=right $dstyle>$pv4h</td>";
      $header .= "<td $dstyle><b>$lblPvRe</b></td> <td align=right $dstyle>$pvRe</td>";
      $header .= "<td $dstyle><b>$lblPvTo</b></td> <td align=right $dstyle>$pvTo</td>";  
      $header .= "</tr>";
  }
  
  
  # Header Information co
  ########################      
  if($hdrDetail eq "all" || $hdrDetail eq "co" || $hdrDetail eq "pvco") {
      $header .= "<tr>";
      $header .= "<td $dstyle><b>CO&nbsp;=></b></td>";
      $header .= "<td $dstyle><b>$lblPvCu</b></td><td align=right $dstyle>$coCu</td>";           
      $header .= "<td $dstyle><b>$lblPv4h</b></td><td align=right $dstyle>$co4h</td>";
      $header .= "<td $dstyle><b>$lblPvRe</b></td><td align=right $dstyle>$coRe</td>";
      $header .= "<td $dstyle><b>$lblPvTo</b></td><td align=right $dstyle>$coTo</td>"; 
      $header .= "</tr>"; 
  }

  $header .= qq{</table>};
  
return $header;
}

################################################################
#    Consumer in forecastGraphic (Balken) anzeigen
#    (Hat zur Zeit keine Wirkung !)
################################################################
sub _showConsumerInGraphicBeam {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $hfcg  = $paref->{hfcg};
  
  my $type  = $hash->{TYPE};
  
  # get consumer list and display it in Graphics
  ################################################ 
  my @consumers = sort{$a<=>$b} keys %{$data{$type}{$name}{consumers}};                          # definierte Verbraucher ermitteln
  
  for (@consumers) {
      next if(!$_);
      my ($itemName, undef) = split(':',$_);
      $itemName =~ s/^\s+|\s+$//gx;                                                              # trim it, if blanks were used
      $_        =~ s/^\s+|\s+$//gx;                                                              # trim it, if blanks were used
    
      # check if listed device is planned
      ####################################
      if (ReadingsVal($name, $itemName."_Planned", "no") eq "yes") {
          #get start and end hour
          my ($start, $end);                                                                     # werden auf Balken Pos 0 - 23 umgerechnet, nicht auf Stunde !!, Pos = 24 -> ungültige Pos = keine Anzeige

          if(AttrVal("global","language","EN") eq "DE") {
              (undef,undef,undef,$start) = ReadingsVal($name, $itemName."_PlannedOpTimeBegin", '00.00.0000 24') =~ m/(\d{2}).(\d{2}).(\d{4})\s(\d{2})/x;
              (undef,undef,undef,$end)   = ReadingsVal($name, $itemName."_PlannedOpTimeEnd",   '00.00.0000 24') =~ m/(\d{2}).(\d{2}).(\d{4})\s(\d{2})/x;
          } 
          else {
              (undef,undef,undef,$start) = ReadingsVal($name, $itemName."_PlannedOpTimeBegin", '0000-00-00 24') =~ m/(\d{4})-(\d{2})-(\d{2})\s(\d{2})/x;
              (undef,undef,undef,$end)   = ReadingsVal($name, $itemName."_PlannedOpTimeEnd",   '0000-00-00 24') =~ m/(\d{4})-(\d{2})-(\d{2})\s(\d{2})/x;
          }

          $start   = int($start);
          $end     = int($end);
          my $flag = 0;                                                                          # default kein Tagesverschieber

          #correct the hour for accurate display
          #######################################
          if ($start < $hfcg->{0}{time}) {                                                       # gridconsumption seems to be tomorrow
              $start = 24-$hfcg->{0}{time}+$start;
              $flag  = 1;
          } 
          else { 
              $start -= $hfcg->{0}{time};          
          }

          if ($flag) {                                                                           # gridconsumption seems to be tomorrow
              $end = 24-$hfcg->{0}{time}+$end;
          } 
          else { 
              $end -= $hfcg->{0}{time}; 
          }

          $_ .= ":".$start.":".$end;
      } 
      else { 
          $_ .= ":24:24"; 
      }
  }
  
return;
}

################################################################
#         Verbraucherlegende und Steuerung 
################################################################
sub _graphicConsumerLegend {                                
  my $paref                    = shift;
  my $hash                     = $paref->{hash};
  my $name                     = $paref->{name};                                                    # Consumer AdviceIcon
  my ($clegendstyle, $clegend) = split('_', $paref->{clegend});
  
  my $type                     = $hash->{TYPE};
  my @consumers                = sort{$a<=>$b} keys %{$data{$type}{$name}{consumers}};              # definierte Verbraucher ermitteln
  
  $clegend                     = '' if(($clegendstyle eq 'none') || (!int(@consumers)));
  $paref->{clegend}            = $clegend;

  return if(!$clegend );
  
  my $ftui   = $paref->{ftui};
  my $lang   = $paref->{lang};
  my $dstyle = $paref->{dstyle};                        # TD-Style
  
  my $staticon;
  
  ## Tabelle Start
  #################
  my $ctable = qq{<table align='left' width='100%'>}; 
  $ctable   .= qq{<tr style='font-weight:bold; text-align:center'>};
  
  $ctable   .= qq{<td style='text-align:left' $dstyle> $hqtxt{cnsm}{$lang}  </td>};
  $ctable   .= qq{<td>                                                      </td>};
  $ctable   .= qq{<td>                                                      </td>};
  $ctable   .= qq{<td $dstyle>                         $hqtxt{eiau}{$lang}  </td>};
  $ctable   .= qq{<td $dstyle>                         $hqtxt{auto}{$lang}  </td>};
  
  my $cnum   = @consumers; 
  if($cnum > 1) {
      $ctable .= qq{<td style='text-align:left' $dstyle> $hqtxt{cnsm}{$lang}  </td>};
      $ctable .= qq{<td>                                                      </td>};
      $ctable .= qq{<td>                                                      </td>};
      $ctable .= qq{<td $dstyle>                         $hqtxt{eiau}{$lang}  </td>};
      $ctable .= qq{<td $dstyle>                         $hqtxt{auto}{$lang}  </td>};
  }
  else {
      my $blk  = '&nbsp;' x 8;
      $ctable .= qq{<td $dstyle> $blk </td>};
      $ctable .= qq{<td>         $blk </td>};
      $ctable .= qq{<td>         $blk </td>};
      $ctable .= qq{<td $dstyle> $blk </td>};
      $ctable .= qq{<td $dstyle> $blk </td>};   
  }
  
  $ctable   .= qq{</tr>};
  
  my $modulo = 1;
  my $tro    = 0;
  
  for my $c (@consumers) { 
      my $caicon     = $paref->{caicon};                                                            # Consumer AdviceIcon
      my $cname      = ConsumerVal ($hash, $c, "name",                    "");                      # Name des Consumerdevices
      my $calias     = ConsumerVal ($hash, $c, "alias",               $cname);                      # Alias des Consumerdevices
      my $cicon      = ConsumerVal ($hash, $c, "icon",                    "");                      # Icon des Consumerdevices     
      my $oncom      = ConsumerVal ($hash, $c, "oncom",                   "");                      # Consumer Einschaltkommando
      my $offcom     = ConsumerVal ($hash, $c, "offcom",                  "");                      # Consumer Ausschaltkommando
      my $autord     = ConsumerVal ($hash, $c, "autoreading",             "");                      # Readingname f. Automatiksteuerung
      my $auto       = ConsumerVal ($hash, $c, "auto",                     1);                      # Automatic Mode
      
      my $cmdon      = qq{"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name consumerAction set $cname $oncom')"};
      my $cmdoff     = qq{"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name consumerAction set $cname $offcom')"};
      my $cmdautoon  = qq{"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name consumerAction setreading $cname $autord 1')"};
      my $cmdautooff = qq{"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name consumerAction setreading $cname $autord 0')"};
      my $implan     = qq{"FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name consumerAction consumerImmediatePlanning $c')"};
      
      if ($ftui eq "ftui") {
          $cmdon      = qq{"ftui.setFhemStatus('set $name consumerAction set $cname $oncom')"};
          $cmdoff     = qq{"ftui.setFhemStatus('set $name consumerAction set $cname $offcom')"};
          $cmdautoon  = qq{"ftui.setFhemStatus('set $name consumerAction set $cname setreading $cname $autord 1')"};  
          $cmdautooff = qq{"ftui.setFhemStatus('set $name consumerAction set $cname setreading $cname $autord 0')"}; 
          $implan     = qq{"ftui.setFhemStatus('set $name consumerAction consumerImmediatePlanning $c')"};          
      }
      
      $cmdon      = q{} if(!$oncom);
      $cmdoff     = q{} if(!$offcom);
      $cmdautoon  = q{} if(!$autord); 
      $cmdautooff = q{} if(!$autord); 

      my $swicon  = q{};                                                                              # Schalter ein/aus Icon
      my $auicon  = q{};                                                                              # Schalter Automatic Icon
      my $isricon = q{};                                                                              # Zustand IsRecommended Icon
            
      $paref->{consumer} = $c;
      
      my ($planstate,$starttime,$stoptime) = __getPlanningStateAndTimes ($paref);      
      my $pstate                           = $caicon eq "times"    ? $hqtxt{pstate}{$lang}  : $htitles{pstate}{$lang};
      my $surplusinfo                      = isConsRcmd($hash, $c) ? $htitles{splus}{$lang} : $htitles{nosplus}{$lang};
      
      $pstate =~ s/<pstate>/$planstate/xs;
      $pstate =~ s/<start>/$starttime/xs;
      $pstate =~ s/<stop>/$stoptime/xs; 
      $pstate =~ s/\s+/&nbsp;/gxs         if($caicon eq "times");      

      if($caicon ne "none") {
          if(isInTimeframe($hash, $c)) {                                                             # innerhalb Planungszeitraum ?
              if($caicon eq "times") {
                  $isricon = $pstate.'<br>'.$surplusinfo;
              }
              else {
                  $isricon = "<a title='$htitles{conrec}{$lang}\n\n$surplusinfo\n$pstate' onClick=$implan>".FW_makeImage($caicon, '')." </a>";
                  if($planstate =~ /priority/xs) {
                      my (undef,$color) = split('@', $caicon);
                      $color            = $color ? '@'.$color : '';  
                      $isricon          = "<a title='$htitles{conrec}{$lang}\n\n$surplusinfo\n$pstate' onClick=$implan>".FW_makeImage('it_ups_charging'.$color, '')." </a>";
                  }
              }
          }
          else {
              if($caicon eq "times") {
                  $isricon =  $pstate.'<br>'.$surplusinfo;
              }
              else {
                  ($caicon) = split('@', $caicon);
                  $isricon  = "<a title='$htitles{connorec}{$lang}\n\n$surplusinfo\n$pstate' onClick=$implan>".FW_makeImage($caicon.'@grey', '')." </a>";
              }
          }
      }      
      
      if($modulo % 2){
          $ctable .= qq{<tr>};
          $tro     = 1;
      }
      
      if(!$auto) {
          $staticon = FW_makeImage('ios_off_fill@red', $htitles{iaaf}{$lang});
          $auicon   = "<a title= '$htitles{iaaf}{$lang}' onClick=$cmdautoon> $staticon</a>";
      } 
      
      if ($auto) {
          $staticon = FW_makeImage('ios_on_till_fill@orange', $htitles{ieas}{$lang});
          $auicon   = "<a title='$htitles{ieas}{$lang}' onClick=$cmdautooff> $staticon</a>";
      }
      
      if (isConsumerPhysOff($hash, $c)) {                                                       # Schaltzustand des Consumerdevices off
          if($cmdon) {
              $staticon = FW_makeImage('ios_off_fill@red', $htitles{iave}{$lang});
              $swicon   = "<a title='$htitles{iave}{$lang}' onClick=$cmdon> $staticon</a>"; 
          }
          else {
              $staticon = FW_makeImage('ios_off_fill@grey', $htitles{ians}{$lang});
              $swicon   = "<a title='$htitles{ians}{$lang}'> $staticon</a>";              
          }
      } 
      
      if (isConsumerPhysOn($hash, $c)) {                                                        # Schaltzustand des Consumerdevices on
          if($cmdoff) {
              $staticon = FW_makeImage('ios_on_fill@green', $htitles{ieva}{$lang});  
              $swicon   = "<a title='$htitles{ieva}{$lang}' onClick=$cmdoff> $staticon</a>";
          }
          else {
              $staticon = FW_makeImage('ios_on_fill@grey', $htitles{iens}{$lang});  
              $swicon   = "<a title='$htitles{iens}{$lang}'> $staticon</a>";              
          }
      }
      
      if ($clegendstyle eq 'icon') {                                                                   
          $cicon   = FW_makeImage($cicon);
          
          $ctable .= "<td style='text-align:left'   $dstyle>$calias         </td>";
          $ctable .= "<td style='text-align:center' $dstyle>$cicon          </td>";
          $ctable .= "<td style='text-align:center' $dstyle>$isricon        </td>";
          $ctable .= "<td style='text-align:center' $dstyle>$swicon         </td>";
          $ctable .= "<td style='text-align:center' $dstyle>$auicon         </td>";
      } 
      else {
          my (undef,$co) = split('@', $cicon);
          $co            = '' if (!$co);                                                                        
          
          $ctable .= "<td style='text-align:left'   $dstyle><font color='$co'>$calias </font></td>";
          $ctable .= "<td>                                                                   </td>";
          $ctable .= "<td>                                  $isricon                         </td>";
          $ctable .= "<td style='text-align:center' $dstyle>$swicon                          </td>";
          $ctable .= "<td style='text-align:center' $dstyle>$auicon                          </td>";
      }
      
      if(!($modulo % 2)) {
          $ctable .= qq{</tr>};
          $tro     = 0;
      }
      
      $modulo++;
  }
  
  delete $paref->{consumer};
  
  $ctable .= qq{</tr>} if($tro);
  $ctable .= qq{</table>};
  
return $ctable;
}

################################################################
#    Werte aktuelle Stunde für forecastGraphic
################################################################
sub _beamGraphicFirstHour {
  my $paref     = shift;
  my $hash      = $paref->{hash};
  my $hfcg      = $paref->{hfcg};
  my $offset    = $paref->{offset};
  my $hourstyle = $paref->{hourstyle};
  my $beam1cont = $paref->{beam1cont};
  my $beam2cont = $paref->{beam2cont};

  my $day;

  my $t                                = NexthoursVal ($hash, "NextHour00", "starttime", '0000-00-00 24');
  my ($year,$month,$day_str,$thishour) = $t =~ m/(\d{4})-(\d{2})-(\d{2})\s(\d{2})/x;
  my ($val1,$val2,$val3,$val4)         = (0,0,0,0);
  
  $thishour++;
  
  $hfcg->{0}{time_str} = $thishour;
  $thishour            = int($thishour);                                                                    # keine führende Null

  $hfcg->{0}{time}     = $thishour;
  $hfcg->{0}{day_str}  = $day_str;
  $day                 = int($day_str);
  $hfcg->{0}{day}      = $day;
  $hfcg->{0}{mktime}   = fhemTimeLocal(0,0,$thishour,$day,int($month)-1,$year-1900);                        # gleich die Unix Zeit dazu holen                                                

  if ($offset) {
      $hfcg->{0}{time} += $offset;

      if ($hfcg->{0}{time} < 0) {
          $hfcg->{0}{time}   += 24;
          my $n_day           = strftime "%d", localtime($hfcg->{0}{mktime} - (3600 * abs($offset)));       # Achtung : Tageswechsel - day muss jetzt neu berechnet werden !
          $hfcg->{0}{day}     = int($n_day);
          $hfcg->{0}{day_str} = $n_day;
      }

      $hfcg->{0}{time_str} = sprintf('%02d', $hfcg->{0}{time});
      
      $val1 = HistoryVal ($hash, $hfcg->{0}{day_str}, $hfcg->{0}{time_str}, "pvfc",  0);
      $val2 = HistoryVal ($hash, $hfcg->{0}{day_str}, $hfcg->{0}{time_str}, "pvrl",  0);
      $val3 = HistoryVal ($hash, $hfcg->{0}{day_str}, $hfcg->{0}{time_str}, "gcons", 0);
      $val4 = HistoryVal ($hash, $hfcg->{0}{day_str}, $hfcg->{0}{time_str}, "confc", 0);

      # $hfcg->{0}{weather} = CircularVal ($hash, $hfcg->{0}{time_str}, "weatherid", 999);
      $hfcg->{0}{weather} = HistoryVal ($hash, $hfcg->{0}{day_str}, $hfcg->{0}{time_str}, "weatherid", 999);
  }
  else {
      $val1 = CircularVal ($hash, $hfcg->{0}{time_str}, "pvfc",  0);
      $val2 = CircularVal ($hash, $hfcg->{0}{time_str}, "pvrl",  0);
      $val3 = CircularVal ($hash, $hfcg->{0}{time_str}, "gcons", 0);
      $val4 = CircularVal ($hash, $hfcg->{0}{time_str}, "confc", 0);

      $hfcg->{0}{weather} = CircularVal ($hash, $hfcg->{0}{time_str}, "weatherid", 999);
      #$val4   = (ReadingsVal($name,"ThisHour_IsConsumptionRecommended",'no') eq 'yes' ) ? $icon : 999;
  }

  $hfcg->{0}{time_str} = sprintf('%02d', $hfcg->{0}{time}-1).$hourstyle;
  $hfcg->{0}{beam1}    = ($beam1cont eq 'pvForecast') ? $val1 : ($beam1cont eq 'pvReal') ? $val2 : ($beam1cont eq 'gridconsumption') ? $val3 : $val4;
  $hfcg->{0}{beam2}    = ($beam2cont eq 'pvForecast') ? $val1 : ($beam2cont eq 'pvReal') ? $val2 : ($beam2cont eq 'gridconsumption') ? $val3 : $val4;
  $hfcg->{0}{diff}     = $hfcg->{0}{beam1} - $hfcg->{0}{beam2};

return ($thishour);
}

################################################################
#    Werte restliche Stunden für forecastGraphic
################################################################
sub _beamGraphicRemainingHours {
  my $paref     = shift;
  my $hash      = $paref->{hash};
  my $hfcg      = $paref->{hfcg};
  my $offset    = $paref->{offset};
  my $maxhours  = $paref->{maxhours};
  my $hourstyle = $paref->{hourstyle};
  my $beam1cont = $paref->{beam1cont};
  my $beam2cont = $paref->{beam2cont};
  my $maxVal    = $paref->{maxVal};                                                                     # dyn. Anpassung der Balkenhöhe oder statisch ?

  $maxVal  //= $hfcg->{0}{beam1};                                                                       # Startwert wenn kein Wert bereits via attr vorgegeben ist

  my ($val1,$val2,$val3,$val4);
  
  my $maxCon = $hfcg->{0}{beam1};                                                                       
  my $maxDif = $hfcg->{0}{diff};                                                                        # für Typ diff
  my $minDif = $hfcg->{0}{diff};                                                                        # für Typ diff

  for my $i (1..($maxhours*2)-1) {                                                                      # doppelte Anzahl berechnen    my $val1 = 0;
      $val2 = 0;
      $val3 = 0;
      $val4 = 0;

      $hfcg->{$i}{time}  = $hfcg->{0}{time} + $i;

      while ($hfcg->{$i}{time} > 24) {
          $hfcg->{$i}{time} -= 24;                                                                      # wird bis zu 2x durchlaufen
      }

      $hfcg->{$i}{time_str} = sprintf('%02d', $hfcg->{$i}{time});

      my $nh;                                                                                           # next hour

      if ($offset < 0) {
          if ($i <= abs($offset)) {                                                                     # $daystr stimmt nur nach Mitternacht, vor Mitternacht muß $hfcg->{0}{day_str} als Basis verwendet werden !
              my $ds = strftime "%d", localtime($hfcg->{0}{mktime} - (3600 * abs($offset+$i)));         # V0.49.4

              # Sonderfall Mitternacht
              $ds   = strftime "%d", localtime($hfcg->{0}{mktime} - (3600 * (abs($offset-$i+1)))) if ($hfcg->{$i}{time} == 24);  # V0.49.4
              
              $val1 = HistoryVal ($hash, $ds, $hfcg->{$i}{time_str}, "pvfc",  0);
              $val2 = HistoryVal ($hash, $ds, $hfcg->{$i}{time_str}, "pvrl",  0); 
              $val3 = HistoryVal ($hash, $ds, $hfcg->{$i}{time_str}, "gcons", 0);
              $val4 = HistoryVal ($hash, $ds, $hfcg->{$i}{time_str}, "confc", 0);
              
              $hfcg->{$i}{weather} = HistoryVal ($hash, $ds, $hfcg->{$i}{time_str}, "weatherid", 999);
          }
          else {
              $nh = sprintf('%02d', $i+$offset);
          }
      }
      else {
          $nh = sprintf('%02d', $i);
      }

      if (defined($nh)) {
          $val1                = NexthoursVal ($hash, 'NextHour'.$nh, "pvforecast",  0);
          $val4                = NexthoursVal ($hash, 'NextHour'.$nh, "confc",       0);
          $hfcg->{$i}{weather} = NexthoursVal ($hash, 'NextHour'.$nh, "weatherid", 999);
          #$val4   = (ReadingsVal($name,"NextHour".$ii."_IsConsumptionRecommended",'no') eq 'yes') ? $icon : undef;
      }

      $hfcg->{$i}{time_str} = sprintf('%02d', $hfcg->{$i}{time}-1).$hourstyle;
      $hfcg->{$i}{beam1}    = ($beam1cont eq 'pvForecast') ? $val1 : ($beam1cont eq 'pvReal') ? $val2 : ($beam1cont eq 'gridconsumption') ? $val3 : $val4;
      $hfcg->{$i}{beam2}    = ($beam2cont eq 'pvForecast') ? $val1 : ($beam2cont eq 'pvReal') ? $val2 : ($beam2cont eq 'gridconsumption') ? $val3 : $val4;

      # sicher stellen das wir keine undefs in der Liste haben !
      $hfcg->{$i}{beam1} //= 0;
      $hfcg->{$i}{beam2} //= 0;
      $hfcg->{$i}{diff}    = $hfcg->{$i}{beam1} - $hfcg->{$i}{beam2};

      $maxVal = $hfcg->{$i}{beam1} if ($hfcg->{$i}{beam1} > $maxVal); 
      $maxCon = $hfcg->{$i}{beam2} if ($hfcg->{$i}{beam2} > $maxCon);
      $maxDif = $hfcg->{$i}{diff}  if ($hfcg->{$i}{diff}  > $maxDif);
      $minDif = $hfcg->{$i}{diff}  if ($hfcg->{$i}{diff}  < $minDif);
  }

  my $back = {
      maxVal => $maxVal,
      maxCon => $maxCon,
      maxDif => $maxDif,
      minDif => $minDif,
  };

return ($back);
}

################################################################
#    Balkenausgabe für forecastGraphic
################################################################
sub _beamGraphic {
  my $paref      = shift;
  my $hash       = $paref->{hash};
  my $name       = $paref->{name};
  my $hfcg       = $paref->{hfcg};
  my $maxhours   = $paref->{maxhours};
  my $weather    = $paref->{weather};
  my $show_night = $paref->{show_night};                     # alle Balken (Spalten) anzeigen ?
  my $show_diff  = $paref->{show_diff};                      # zusätzliche Anzeige $di{} in allen Typen
  my $lotype     = $paref->{lotype};
  my $height     = $paref->{height};
  my $fsize      = $paref->{fsize};
  my $kw         = $paref->{kw};
  my $colorfc    = $paref->{colorfc};
  my $colorc     = $paref->{colorc};
  my $fcolor1    = $paref->{fcolor1};
  my $fcolor2    = $paref->{fcolor2}; 
  my $offset     = $paref->{offset};
  my $thishour   = $paref->{thishour};
  my $maxVal     = $paref->{maxVal};                         
  my $maxCon     = $paref->{maxCon};                                                                       
  my $maxDif     = $paref->{maxDif};                                                           
  my $minDif     = $paref->{minDif}; 
  my $beam1cont  = $paref->{beam1cont};
  my $beam2cont  = $paref->{beam2cont};
  
  $lotype        = 'single' if ($beam1cont eq $beam2cont);                                                       # User Auswahl Layout überschreiben bei gleichen Beamcontent !

  # Wenn Table class=block alleine steht, zieht es bei manchen Styles die Ausgabe auf 100% Seitenbreite
  # lässt sich durch einbetten in eine zusätzliche Table roomoverview eindämmen
  # Die Tabelle ist recht schmal angelegt, aber nur so lassen sich Umbrüche erzwingen
  
  my ($val,$z2,$z3,$z4,$he);
  my $ret;
  
  $ret .= __weatherOnBeam ($paref);
  
  my $m = $paref->{modulo} % 2;

  if($show_diff eq 'top') {                                                                                      # Zusätzliche Zeile Ertrag - Verbrauch
      $ret .= "<tr class='$htr{$m}{cl}'><td class='solarfc'></td>";
      my $ii;
      for my $i (0..($maxhours*2)-1) {                                                                           # gleiche Bedingung wie oben      
          next if (!$show_night && ($hfcg->{$i}{weather} > 99) 
                                && !$hfcg->{$i}{beam1} 
                                && !$hfcg->{$i}{beam2});
          $ii++;                                                                                                 # wieviele Stunden haben wir bisher angezeigt ?
          
          last if ($ii > $maxhours);                                                                             # vorzeitiger Abbruch

          $val  = formatVal6($hfcg->{$i}{diff},$kw,$hfcg->{$i}{weather});
          
          if ($val ne '&nbsp;') {                                                                                # Forum: https://forum.fhem.de/index.php/topic,117864.msg1166215.html#msg1166215
          $val  = $hfcg->{$i}{diff} < 0 ? 
                  '<b>'.$val.'<b/>'     : 
                  $val > 0              ? 
                  '+'.$val              : 
                  $val;                                                                                          # negative Zahlen in Fettschrift, 0 aber ohne +
          }
          
          $ret .= "<td class='solarfc' style='vertical-align:middle; text-align:center;'>$val</td>"; 
      }
      $ret .= "<td class='solarfc'></td></tr>";                                                                  # freier Platz am Ende 
  }

  $ret .= "<tr class='$htr{$m}{cl}'><td class='solarfc'></td>";                                                  # Neue Zeile mit freiem Platz am Anfang

  my $ii = 0;
  
  for my $i (0..($maxhours*2)-1) {                                                                               # gleiche Bedingung wie oben
      next if (!$show_night && defined($hfcg->{$i}{weather}) 
                            && ($hfcg->{$i}{weather} > 99) 
                            && !$hfcg->{$i}{beam1} 
                            && !$hfcg->{$i}{beam2});
      $ii++;
      last if ($ii > $maxhours);

      # Achtung Falle, Division by Zero möglich, 
      # maxVal kann gerade bei kleineren maxhours Ausgaben in der Nacht leicht auf 0 fallen  
      $height = 200 if (!$height);                                                                               # Fallback, sollte eigentlich nicht vorkommen, außer der User setzt es auf 0
      $maxVal = 1   if (!int $maxVal);
      $maxCon = 1   if (!$maxCon);

      # Der zusätzliche Offset durch $fsize verhindert bei den meisten Skins 
      # dass die Grundlinie der Balken nach unten durchbrochen wird

      if ($lotype eq 'single') {
          $he = int(($maxVal-$hfcg->{$i}{beam1}) / $maxVal*$height) + $fsize;
          $z3 = int($height + $fsize - $he);
      } 

      if ($lotype eq 'double') {
          # Berechnung der Zonen
          # he - freier der Raum über den Balken. fsize wird nicht verwendet, da bei diesem Typ keine Zahlen über den Balken stehen 
          # z2 - der Ertrag ggf mit Icon
          # z3 - der Verbrauch , bei zu kleinem Wert wird der Platz komplett Zone 2 zugeschlagen und nicht angezeigt
          # z2 und z3 nach Bedarf tauschen, wenn der Verbrauch größer als der Ertrag ist

          $maxVal = $maxCon if ($maxCon > $maxVal);                                                              # wer hat den größten Wert ?

          if ($hfcg->{$i}{beam1} > $hfcg->{$i}{beam2}) {                                                         # Beam1 oben , Beam2 unten
              $z2 = $hfcg->{$i}{beam1}; $z3 = $hfcg->{$i}{beam2}; 
          } 
          else {                                                                                                 # tauschen, Verbrauch ist größer als Ertrag
              $z3 = $hfcg->{$i}{beam1}; $z2 = $hfcg->{$i}{beam2}; 
          }

          $he = int(($maxVal-$z2)/$maxVal*$height);
          $z2 = int(($z2 - $z3)/$maxVal*$height);

          $z3 = int($height - $he - $z2);                                                                        # was von maxVal noch übrig ist
              
          if ($z3 < int($fsize/2)) {                                                                             # dünnen Strichbalken vermeiden / ca. halbe Zeichenhöhe
              $z2 += $z3; 
              $z3  = 0; 
          }
      }

      if ($lotype eq 'diff') {                                                              
          # Berechnung der Zonen
          # he - freier der Raum über den Balken , Zahl positiver Wert + fsize
          # z2 - positiver Balken inkl Icon
          # z3 - negativer Balken
          # z4 - Zahl negativer Wert + fsize

          my ($px_pos,$px_neg);
          my $maxValBeam = 0;                                                                                    # ToDo:  maxValBeam noch aus Attribut maxValBeam ableiten

          if ($maxValBeam) {                                                                                     # Feste Aufteilung +/- , jeder 50 % bei maxValBeam = 0
              $px_pos = int($height/2);
              $px_neg = $height - $px_pos;                                                                       # Rundungsfehler vermeiden
          } 
          else {                                                                                                 # Dynamische hoch/runter Verschiebung der Null-Linie        
              if ($minDif >= 0 ) {                                                                               # keine negativen Balken vorhanden, die Positiven bekommen den gesammten Raum
                  $px_neg = 0;
                  $px_pos = $height;
              } 
              else {
                  if ($maxDif > 0) {
                      $px_neg = int($height * abs($minDif) / ($maxDif + abs($minDif)));                          # Wieviel % entfallen auf unten ?
                      $px_pos = $height-$px_neg;                                                                 # der Rest ist oben
                  }
                  else {                                                                                         # keine positiven Balken vorhanden, die Negativen bekommen den gesammten Raum
                      $px_neg = $height;
                      $px_pos = 0;
                  }
              }
          }

          if ($hfcg->{$i}{diff} >= 0) {                                                                          # Zone 2 & 3 mit ihren direkten Werten vorbesetzen
              $z2 = $hfcg->{$i}{diff};
              $z3 = abs($minDif);
          } 
          else {
              $z2 = $maxDif;
              $z3 = abs($hfcg->{$i}{diff});                                                                      # Nur Betrag ohne Vorzeichen
          }
                                                                                                                 # Alle vorbesetzen Werte umrechnen auf echte Ausgabe px
          $he = (!$px_pos || !$maxDif) ? 0 : int(($maxDif-$z2)/$maxDif*$px_pos);                                 # Teilung durch 0 vermeiden
          $z2 = ($px_pos - $he) ;

          $z4 = (!$px_neg || !$minDif) ? 0 : int((abs($minDif)-$z3)/abs($minDif)*$px_neg);                       # Teilung durch 0 unbedingt vermeiden
          $z3 = ($px_neg - $z4);
                                                                                                                 # Beiden Zonen die Werte ausgeben könnten muß fsize als zusätzlicher Raum zugeschlagen werden !
          $he += $fsize; 
          $z4 += $fsize if ($z3);                                                                                # komplette Grafik ohne negativ Balken, keine Ausgabe von z3 & z4
      }
        
      # das style des nächsten TD bestimmt ganz wesentlich das gesammte Design
      # das \n erleichtert das lesen des Seitenquelltext beim debugging
      # vertical-align:bottom damit alle Balken und Ausgaben wirklich auf der gleichen Grundlinie sitzen

      $ret .="<td style='text-align: center; padding-left:1px; padding-right:1px; margin:0px; vertical-align:bottom; padding-top:0px'>\n";

      if ($lotype eq 'single') {
          $val = formatVal6($hfcg->{$i}{beam1},$kw,$hfcg->{$i}{weather});

          $ret .="<table width='100%' height='100%'>";                                                           # mit width=100% etwas bessere Füllung der Balken
          $ret .="<tr class='$htr{$m}{cl}' style='height:".$he."px'>";
          $ret .="<td class='solarfc' style='vertical-align:bottom; color:#$fcolor1;'>".$val.'</td></tr>';

          if ($hfcg->{$i}{beam1} || $show_night) {                                                               # Balken nur einfärben wenn der User via Attr eine Farbe vorgibt, sonst bestimmt class odd von TR alleine die Farbe
              my $style = "style=\"padding-bottom:0px; vertical-align:top; margin-left:auto; margin-right:auto;";
              $style   .= defined $colorfc ? " background-color:#$colorfc\"" : '"';                              # Syntaxhilight 

              $ret .= "<tr class='odd' style='height:".$z3."px;'>";
              $ret .= "<td align='center' class='solarfc' ".$style.">";
                      
              my $sicon = 1;                                                    
              #$ret .= $is{$i} if (defined ($is{$i}) && $sicon);

              # inject the new icon if defined
              ##################################
              #$ret .= consinject($hash,$i,@consumers) if($s);
                      
              $ret .= "</td></tr>";
          }
      }
    
      if ($lotype eq 'double') {
          my ($color1, $color2, $style1, $style2, $v);
          my $style =  "style='padding-bottom:0px; padding-top:1px; vertical-align:top; margin-left:auto; margin-right:auto;";

          $ret .="<table width='100%' height='100%'>\n";                                                         # mit width=100% etwas bessere Füllung der Balken
                                                                                                                 # der Freiraum oben kann beim größten Balken ganz entfallen
          $ret .="<tr class='$htr{$m}{cl}' style='height:".$he."px'><td class='solarfc'></td></tr>" if ($he);

          if($hfcg->{$i}{beam1} > $hfcg->{$i}{beam2}) {                                                          # wer ist oben, Beam2 oder Beam1 ? Wert und Farbe für Zone 2 & 3 vorbesetzen
              $val     = formatVal6($hfcg->{$i}{beam1},$kw,$hfcg->{$i}{weather});
              $color1  = $colorfc;
              $style1  = $style." background-color:#$color1; color:#$fcolor1;'";

              if($z3) {                                                                                          # die Zuweisung können wir uns sparen wenn Zone 3 nachher eh nicht ausgegeben wird
                  $v       = formatVal6($hfcg->{$i}{beam2},$kw,$hfcg->{$i}{weather});
                  $color2  = $colorc;
                  $style2  = $style." background-color:#$color2; color:#$fcolor2;'";
              }
          }
          else {
              $val     = formatVal6($hfcg->{$i}{beam2},$kw,$hfcg->{$i}{weather});
              $color1  = $colorc;
              $style1  = $style." background-color:#$color1; color:#$fcolor2;'";
       
              if($z3) {
                  $v       = formatVal6($hfcg->{$i}{beam1},$kw,$hfcg->{$i}{weather});
                  $color2  = $colorfc;
                  $style2  = $style." background-color:#$color2; color:#$fcolor1;'";
              }
          }

          $ret .= "<tr class='odd' style='height:".$z2."px'>";
          $ret .= "<td align='center' class='solarfc' ".$style1.">$val";
             
          # inject the new icon if defined
          ##################################
          #$ret .= consinject($hash,$i,@consumers) if($s);
             
          $ret .= "</td></tr>";

          if ($z3) {                                                                                             # die Zone 3 lassen wir bei zu kleinen Werten auch ganz weg 
              $ret .= "<tr class='odd' style='height:".$z3."px'>";
              $ret .= "<td align='center' class='solarfc' ".$style2.">$v</td></tr>";
          }
      }

      if ($lotype eq 'diff') {                                                                                   # Type diff
          my $style = "style='padding-bottom:0px; padding-top:1px; vertical-align:top; margin-left:auto; margin-right:auto;";
          $ret .= "<table width='100%' border='0'>\n";                                                           # Tipp : das nachfolgende border=0 auf 1 setzen hilft sehr Ausgabefehler zu endecken

          $val = ($hfcg->{$i}{diff} > 0) ? formatVal6($hfcg->{$i}{diff},$kw,$hfcg->{$i}{weather}) : '';
          $val = '&nbsp;&nbsp;&nbsp;0&nbsp;&nbsp;' if ($hfcg->{$i}{diff} == 0);                                  # Sonderfall , hier wird die 0 gebraucht !

          if ($val) {
              $ret .= "<tr class='$htr{$m}{cl}' style='height:".$he."px'>";
              $ret .= "<td class='solarfc' style='vertical-align:bottom; color:#$fcolor1;'>".$val."</td></tr>";
          }

          if ($hfcg->{$i}{diff} >= 0) {                                                                          # mit Farbe 1 colorfc füllen
              $style .= " background-color:#$colorfc'";
              $z2     = 1 if ($hfcg->{$i}{diff} == 0);                                                           # Sonderfall , 1px dünnen Strich ausgeben
              $ret   .= "<tr class='odd' style='height:".$z2."px'>";
              $ret   .= "<td align='center' class='solarfc' ".$style.">";
              $ret   .= "</td></tr>";
          } 
          else {                                                                                                 # ohne Farbe
              $z2 = 2 if ($hfcg->{$i}{diff} == 0);                                                               # Sonderfall, hier wird die 0 gebraucht !
              if ($z2 && $val) {                                                                                 # z2 weglassen wenn nicht unbedigt nötig bzw. wenn zuvor he mit val keinen Wert hatte
                  $ret .= "<tr class='$htr{$m}{cl}' style='height:".$z2."px'>";
                  $ret .= "<td class='solarfc'></td></tr>";
              }
          }
        
          if ($hfcg->{$i}{diff} < 0) {                                                                           # Negativ Balken anzeigen ?
              $style .= " background-color:#$colorc'";                                                           # mit Farbe 2 colorc füllen
              $ret   .= "<tr class='odd' style='height:".$z3."px'>";
              $ret   .= "<td align='center' class='solarfc' ".$style."></td></tr>";
          }
          elsif ($z3) {                                                                                          # ohne Farbe
              $ret .= "<tr class='$htr{$m}{cl}' style='height:".$z3."px'>";
              $ret .= "<td class='solarfc'></td></tr>";
          }

          if($z4) {                                                                                              # kann entfallen wenn auch z3 0 ist
              $val  = ($hfcg->{$i}{diff} < 0) ? formatVal6($hfcg->{$i}{diff},$kw,$hfcg->{$i}{weather}) : '&nbsp;';
              $ret .= "<tr class='$htr{$m}{cl}' style='height:".$z4."px'>";
              $ret .= "<td class='solarfc' style='vertical-align:top'>".$val."</td></tr>";
          }
      }

      if ($show_diff eq 'bottom') {                                                                              # zusätzliche diff Anzeige
          $val  = formatVal6($hfcg->{$i}{diff},$kw,$hfcg->{$i}{weather});
          $val  = ($hfcg->{$i}{diff} < 0) ?  '<b>'.$val.'<b/>' : ($val > 0 ) ? '+'.$val : $val if ($val ne '&nbsp;'); # negative Zahlen in Fettschrift, 0 aber ohne +
          $ret .= "<tr class='$htr{$m}{cl}'><td class='solarfc' style='vertical-align:middle; text-align:center;'>$val</td></tr>"; 
      }

      $ret .= "<tr class='$htr{$m}{cl}'><td class='solarfc' style='vertical-align:bottom; text-align:center;'>";
      $ret .= (($hfcg->{$i}{time} == $thishour) && ($offset < 0)) ? '<a class="changed" style="visibility:visible"><span>'.$hfcg->{$i}{time_str}.'</span></a>' : $hfcg->{$i}{time_str};
      
      if($hfcg->{$i}{time} == $thishour) {
          $thishour = 99;                                                                                        # nur einmal verwenden !
      }
      
      $ret .="</td></tr></table></td>";                                                   
  }
  
  $paref->{modulo}++;

  $ret .= "<td class='solarfc'></td>";
  $ret .= "</tr>";

return $ret;
}

################################################################
#                   Wetter Icon Zeile 
################################################################
sub __weatherOnBeam {
  my $paref      = shift;
  my $name       = $paref->{name};
  my $hfcg       = $paref->{hfcg};
  my $maxhours   = $paref->{maxhours};
  my $weather    = $paref->{weather};
  my $show_night = $paref->{show_night};                     # alle Balken (Spalten) anzeigen ?
  my $colorw     = $paref->{colorw};                         # Wetter Icon Farbe
  my $colorwn    = $paref->{colorwn};                        # Wetter Icon Farbe Nacht
  my $width      = $paref->{width};
  
  my $ret = q{};
  
  return $ret if(!$weather);
  
  my $m = $paref->{modulo} % 2;

  $ret .= "<tr class='$htr{$m}{cl}'><td class='solarfc'></td>";                                              # freier Platz am Anfang

  my $ii;
  for my $i (0..($maxhours*2)-1) {
      last if (!exists($hfcg->{$i}{weather}));
      next if (!$show_night  && defined($hfcg->{$i}{weather}) 
                             && ($hfcg->{$i}{weather} > 99) 
                             && !$hfcg->{$i}{beam1} 
                             && !$hfcg->{$i}{beam2});
                                                                                                             # Lässt Nachticons aber noch durch wenn es einen Wert gibt , ToDo : klären ob die Nacht richtig gesetzt wurde
      $ii++;                                                                                                 # wieviele Stunden Icons haben wir bisher beechnet  ?
      last if ($ii > $maxhours);
                                                                                                             # ToDo : weather_icon sollte im Fehlerfall Title mit der ID besetzen um in FHEMWEB sofort die ID sehen zu können
      if (exists($hfcg->{$i}{weather}) && defined($hfcg->{$i}{weather})) {
          my ($icon_name, $title) = $hfcg->{$i}{weather} > 100             ? 
                                    weather_icon($hfcg->{$i}{weather}-100) : 
                                    weather_icon($hfcg->{$i}{weather});
          
          if($icon_name eq 'unknown') {              
              Log3 ($name, 4, "$name - unknown weather id: ".$hfcg->{$i}{weather}.", please inform the maintainer");
          }
              
          $icon_name .= $hfcg->{$i}{weather} < 100 ? '@'.$colorw  : '@'.$colorwn;
          my $val     = FW_makeImage($icon_name) // q{};

          if ($val eq $icon_name) {                                                                          # passendes Icon beim User nicht vorhanden ! ( attr web iconPath falsch/prüfen/update ? )
              $val = '<b>???<b/>';
              if(AttrVal ($name, "debug", 0)) {                                                              # nur für Debugging
                  Log (1, qq{DEBUG> $name - the icon "$weather_ids{$hfcg->{$i}{weather}}{icon}" not found. Please check attribute "iconPath" of your FHEMWEB instance and/or update your FHEM software});
              }
          }
          
          $ret .= "<td title='$title' class='solarfc' width='$width' style='margin:1px; vertical-align:middle align:center; padding-bottom:1px;'>$val</td>";
      } 
      else {                                                                                                 # mit $hfcg->{$i}{weather} = undef kann man unten leicht feststellen ob für diese Spalte bereits ein Icon ausgegeben wurde oder nicht
          $ret .= "<td></td>";  
          $hfcg->{$i}{weather} = undef;                                                                      # ToDo : prüfen ob noch nötig
      }
  }

  $ret .= "<td class='solarfc'></td></tr>";                                                                  # freier Platz am Ende der Icon Zeile

return $ret;
}

################################################################
#                  Energieflußgrafik
################################################################
sub _flowGraphic {
  my $paref         = shift;
  my $hash          = $paref->{hash};
  my $name          = $paref->{name};
  my $flowgh        = $paref->{flowgh};
  my $flowgani      = $paref->{flowgani};
  my $flowgcons     = $paref->{flowgcons};
  my $flowgconX     = $paref->{flowgconX};
  my $flowgconPower = $paref->{flowgconsPower};
  my $flowgconTime  = $paref->{flowgconsTime};
  my $consDist      = $paref->{flowgconsDist};
  my $css           = $paref->{css};
  
  my $style      = 'width:'.$flowgh.'px; height:'.$flowgh.'px;';
  my $animation  = $flowgani ? '@keyframes dash {  to {  stroke-dashoffset: 0;  } }' : '';             # Animation Ja/Nein
  my $cpv        = ReadingsNum($name, 'Current_PV',              0);
  my $cgc        = ReadingsNum($name, 'Current_GridConsumption', 0);
  my $cgfi       = ReadingsNum($name, 'Current_GridFeedIn',      0);
  my $csc        = ReadingsNum($name, 'Current_SelfConsumption', 0);
  my $cc         = ReadingsNum($name, 'Current_Consumption',     0);
  my $cc_dummy   = $cc;
  my $batin      = ReadingsNum($name, 'Current_PowerBatIn',  undef);
  my $batout     = ReadingsNum($name, 'Current_PowerBatOut', undef);
  my $soc        = ReadingsNum($name, 'Current_BatCharge',     100);
  
  my $bat_color  = $soc < 26 ? 'flowg bat25' : 
                   $soc < 76 ? 'flowg bat50' : 
                   'flowg bat75';
                   
  my $hasbat     = 1;

  if (!defined($batin) && !defined($batout)) {
      $hasbat = 0;
      $batin  = 0;
      $batout = 0;
      $soc    = 0;
  }
  else {
      $csc -= $batout;
  }
  
  my $grid_color    = $cgfi   ? 'flowg grid_color1'               : 'flowg grid_color2';
  $grid_color       = 'flowg grid_color3'  if (!$cgfi && !$cgc && $batout);                    # dritte Farbe
  my $cgc_style     = $cgc    ? 'flowg active_in'                 : 'flowg inactive_in';
  my $batout_style  = $batout ? 'flowg active_out active_bat_out' : 'flowg inactive_in';
  
  my $cgc_direction = 'M490,305 L670,510';                             # Batterientladung ins Netz                 
  
  if($batout) {                                                        
      my $cgfo = $cgfi - $cpv;

      if($cgfo > 1) {
        $cgc_style     = 'flowg active_out';
        $cgc_direction = 'M670,510 L490,305';
        $cgfi         -= $cgfo;
        $cgc           = $cgfo; 
      }
  }
  
  my $batout_direction  =  'M902,305 L730,510';                        # Batterientladung aus Netz
  
  if($batin) {
      my $gbi = $batin - $cpv;

      if($gbi > 1) {
        $batin            -= $gbi;
        $batout_style      = 'flowg active_in';
        $batout_direction  = 'M730,510 L902,305';
        $batout            = $gbi; 
      }
  }
  
  my $sun_color    = $cpv         ? 'flowg sun_active'              : 'flowg sun_inactive';
  my $batin_style  = $batin       ? 'flowg active_in active_bat_in' : 'flowg inactive_out';
  my $csc_style    = $csc && $cpv ? 'flowg active_out'              : 'flowg inactive_out';
  my $cgfi_style   = $cgfi        ? 'flowg active_out'              : 'flowg inactive_out';
  
  my $ret = << "END0";
      <style>
      $css
      $animation
      </style>
     
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="5 15 780 780" style="$style" id="SVGPLOT">
      
      <g transform="translate(400,50)">
        <g>
            <line class="$sun_color" stroke-linecap="round" stroke-width="5" transform="translate(0,9)" x1="0" x2="0" y1="16" y2="24" />
        </g>
        <g transform="rotate(45)">
            <line class="$sun_color" stroke-linecap="round" stroke-width="5" transform="translate(0,9)" x1="0" x2="0" y1="16" y2="24" />
        </g>
        <g transform="rotate(90)">
            <line class="$sun_color" stroke-linecap="round" stroke-width="5" transform="translate(0,9)" x1="0" x2="0" y1="16" y2="24" />
        </g>
        <g transform="rotate(135)">
            <line class="$sun_color" stroke-linecap="round" stroke-width="5" transform="translate(0,9)" x1="0" x2="0" y1="16" y2="24" />
        </g>
        <g transform="rotate(180)">
            <line class="$sun_color" stroke-linecap="round" stroke-width="5" transform="translate(0,9)" x1="0" x2="0" y1="16" y2="24" />
        </g>
        <g transform="rotate(225)">
            <line class="$sun_color" stroke-linecap="round" stroke-width="5" transform="translate(0,9)" x1="0" x2="0" y1="16" y2="24" />
        </g>
        <g transform="rotate(270)">
            <line class="$sun_color" stroke-linecap="round" stroke-width="5" transform="translate(0,9)" x1="0" x2="0" y1="16" y2="24" />
        </g>
        <g transform="rotate(315)">
            <line class="$sun_color" stroke-linecap="round" stroke-width="5" transform="translate(0,9)" x1="0" x2="0" y1="16" y2="24" />
        </g>
        <circle cx="0" cy="0" class="$sun_color" r="16" stroke-width="2"/>
      </g>

      <g id="home" fill="grey" transform="translate(350,310),scale(4)">
          <path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/>
      </g>    

      <g id="grid" class="$grid_color" transform="translate(200,150),scale(3.5)">
          <path d="M15.3,2H8.7L2,6.46V10H4V8H8v2.79l-4,9V22H6V20.59l6-3.27,6,3.27V22h2V19.79l-4-9V8h4v2h2V6.46ZM14,4V6H10V4ZM6.3,6,8,4.87V6Zm8,6L15,13.42,12,15,9,13.42,9.65,12ZM7.11,17.71,8.2,15.25l1.71.93Zm8.68-2.46,1.09,2.46-2.8-1.53ZM14,10H10V8h4Zm2-5.13L17.7,6H16Z"/>
      </g>
END0

  ## get consumer list and display it in Graphics
  ################################################
  my $pos_left       = 0;
  my $consumercount  = 0;
  my $consumer_start = 0;
  my $currentPower   = 0;
  my @consumers;
  
  if ($flowgcons) {
      my $type       = $hash->{TYPE};
      @consumers     = sort{$a<=>$b} keys %{$data{$type}{$name}{consumers}};                        # definierte Verbraucher ermitteln
      $consumercount = scalar @consumers; 

      if ($consumercount % 2) {
          $consumer_start = 350 - ($consDist  * (($consumercount -1) / 2)); 
      } 
      else {
          $consumer_start = 350 - ((($consDist ) / 2) * ($consumercount-1));
      }
      
      $consumer_start = 0 if $consumer_start < 0;
      $pos_left       = $consumer_start + 15;
      
      for my $c0 (@consumers) {
          my $calias      = ConsumerVal       ($hash, $c0, "alias", "");                            # Name des Consumerdevices
          $currentPower   = ReadingsNum       ($name, "consumer${c0}_currentPower", 0);
          my $cicon       = substConsumerIcon ($hash, $c0);                                         # Icon des Consumerdevices
          $cc_dummy      -= $currentPower;
          
          $ret .= '<g id="consumer_'.$c0.'" fill="grey" transform="translate('.$pos_left.',485),scale(0.1)">';
          $ret .= "<title>$calias</title>".FW_makeImage($cicon, '');
          $ret .= '</g> ';
        
          $pos_left += $consDist;
      }
  }

  if ($hasbat) {
      $ret .= << "END1";
      <g class="$bat_color" transform="translate(610,135),scale(.33) rotate (90)">
      <path d="m 134.65625,89.15625 c -6.01649,0 -11,4.983509 -11,11 l 0,180 c 0,6.01649 4.98351,11 11,11 l 95.5,0 c 6.01631,0 11,-4.9825 11,-11 l 0,-180 c 0,-6.016491 -4.98351,-11 -11,-11 l -95.5,0 z m 0,10 95.5,0 c 0.60951,0 1,0.390491 1,1 l 0,180 c 0,0.6085 -0.39231,1 -1,1 l -95.5,0 c -0.60951,0 -1,-0.39049 -1,-1 l 0,-180 c 0,-0.609509 0.39049,-1 1,-1 z"/>
      <path d="m 169.625,69.65625 c -6.01649,0 -11,4.983509 -11,11 l 0,14 10,0 0,-14 c 0,-0.609509 0.39049,-1 1,-1 l 25.5,0 c 0.60951,0 1,0.390491 1,1 l 0,14 10,0 0,-14 c 0,-6.016491 -4.98351,-11 -11,-11 l -25.5,0 z"/>
END1

      $ret .= '<path d="m 221.141,266.334 c 0,3.313 -2.688,6 -6,6 h -65.5 c -3.313,0 -6,-2.688 -6,-6 v -6 c 0,-3.314 2.687,-6 6,-6 l 65.5,-20 c 3.313,0 6,2.686 6,6 v 26 z"/>'     if ($soc > 12);
      $ret .= '<path d="m 221.141,213.667 c 0,3.313 -2.688,6 -6,6 l -65.5,20 c -3.313,0 -6,-2.687 -6,-6 v -20 c 0,-3.313 2.687,-6 6,-6 l 65.5,-20 c 3.313,0 6,2.687 6,6 v 20 z"/>' if ($soc > 38);
      $ret .= '<path d="m 221.141,166.667 c 0,3.313 -2.688,6 -6,6 l -65.5,20 c -3.313,0 -6,-2.687 -6,-6 v -20 c 0,-3.313 2.687,-6 6,-6 l 65.5,-20 c 3.313,0 6,2.687 6,6 v 20 z"/>' if ($soc > 63);
      $ret .= '<path d="m 221.141,120 c 0,3.313 -2.688,6 -6,6 l -65.5,20 c -3.313,0 -6,-2.687 -6,-6 v -26 c 0,-3.313 2.687,-6 6,-6 h 65.5 c 3.313,0 6,2.687 6,6 v 6 z"/>'          if ($soc > 88);
      $ret .= '</g>';
  }
  
  if ($flowgconX) {                                                                                # Dummy Consumer
      $ret .= '<g id="consumer_X" fill="grey" transform="translate(520,330),scale(0.1)">';
      $ret .= "<title>consumer_X</title>".FW_makeImage('light_light_dim_100', '');
      $ret .= '</g> ';
   }
   
    $ret .= << "END2";
    <g transform="translate(50,50),scale(0.5)" stroke-width="27" fill="none">
    <path id="pv-home"   class="$csc_style"  d="M700,100 L700,510" />
    <path id="pv-grid"   class="$cgfi_style" d="M670,100 L490,270" />
    <path id="grid-home" class="$cgc_style"  d="$cgc_direction" />
END2

  if ($hasbat) {
      $ret .= << "END3";
      <path id="bat-home" class="$batout_style" d="$batout_direction" />
      <path id="pv-bat"   class="$batin_style"  d="M730,100 L900,270" />
END3
  }
  
   if ($flowgconX) {                                                                              # Dummy Consumer 
      my $consumer_style = 'flowg inactive_out';
      $consumer_style    = 'flowg active_out' if($cc_dummy > 1);
          
      my $chain_color = "";                                                                       # Farbe der Laufkette Donsumer-Dummy
      if($cc_dummy > 0.5) {
          $chain_color  = 'style="stroke: #'.substr(Color::pahColor(0,500,1000,$cc_dummy,[0,255,0, 127,255,0, 255,255,0, 255,127,0, 255,0,0]),0,6).';"';
          #$chain_color  = 'style="stroke: #DF0101;"';
      }
      
      $ret .= qq{<path id="home-consumer_X" class="$consumer_style" $chain_color d="M780,620 L930,620" />};  
   }
  
  ## get consumer list and display it in Graphics
  ################################################
  if ($flowgcons) {
      $pos_left          = $consumer_start * 2;
      my $pos_left_start = 0;
      my $distance       = 25;
      
      if ($consumercount % 2) {
          $pos_left_start = 700 - ($distance  * (($consumercount -1) / 2)); 
      } 
      else {
          $pos_left_start = 700 - ((($distance ) / 2) * ($consumercount-1));
      }
      
      for my $c1 (@consumers) {     
          my $power          = ConsumerVal ($hash, $c1, "power",   0);
          my $rpcurr         = ConsumerVal ($hash, $c1, "rpcurr", "");                              # Reading für akt. Verbrauch angegeben ?
          $currentPower      = ReadingsNum ($name, "consumer${c1}_currentPower", 0);
          
          if (!$rpcurr && isConsumerPhysOn($hash, $c1)) {                                           # Workaround wenn Verbraucher ohne Leistungsmessung
              $currentPower = $power;
          }
          
          my $p              = $currentPower;    
          $p                 = (($currentPower / $power) * 100) if ($power > 0);
             
          my $consumer_style = 'flowg inactive_out';
          $consumer_style    = 'flowg active_out' if($p > $defpopercent);
         
          my $chain_color = "";                                                                     # Farbe der Laufkette des Consumers
          if($p > 0.5) {
              $chain_color  = 'style="stroke: #'.substr(Color::pahColor(0,50,100,$p,[0,255,0, 127,255,0, 255,255,0, 255,127,0, 255,0,0]),0,6).';"';
              #$chain_color  = 'style="stroke: #DF0101;"';
          }
         
          $ret            .= qq{<path id="home-consumer_$c1" class="$consumer_style" $chain_color d="M$pos_left_start,700 L$pos_left,850" />};
         
          $pos_left       += ($consDist * 2);
          $pos_left_start += $distance;
      } 
  }
  
  ## Angaben Dummy-Verbraucher 
  #############################
  
  $cc_dummy = sprintf("%.0f",$cc_dummy);

  $ret .= qq{<text class="flowg text" id="pv-txt"        x="800" y="15"  style="text-anchor: start;">$cpv</text>}        if ($cpv);
  $ret .= qq{<text class="flowg text" id="bat-txt"       x="995" y="370" style="text-anchor: middle;">$soc %</text>}     if ($hasbat);
  $ret .= qq{<text class="flowg text" id="pv_home-txt"   x="730" y="300" style="text-anchor: start;">$csc</text>}        if ($csc && $cpv);
  $ret .= qq{<text class="flowg text" id="pv-grid-txt"   x="525" y="200" style="text-anchor: end;">$cgfi</text>}         if ($cgfi);
  $ret .= qq{<text class="flowg text" id="grid-home-txt" x="525" y="420" style="text-anchor: end;">$cgc</text>}          if ($cgc);
  $ret .= qq{<text class="flowg text" id="batout-txt"    x="865" y="420" style="text-anchor: start;">$batout</text>}     if ($batout && $hasbat);
  $ret .= qq{<text class="flowg text" id="batin-txt"     x="865" y="200" style="text-anchor: start;">$batin</text>}      if ($batin && $hasbat);
  $ret .= qq{<text class="flowg text" id="home-txt"      x="600" y="620" style="text-anchor: end;">$cc</text>};                                               # Current_Consumption Anlage
  $ret .= qq{<text class="flowg text" id="dummy-txt"     x="1070" y="620" style="text-anchor: start;">$cc_dummy</text>}  if ($flowgconX && $flowgconPower);   # Current_Consumption Dummy
  
  ## Anzeigedetails auswählen
  ############################
  if ($flowgcons) {
      $pos_left = ($consumer_start * 2) - 50;
      
      for my $c2 (@consumers) {      
          $currentPower    = sprintf("%.1f", ReadingsNum($name, "consumer${c2}_currentPower", 0));
          my $consumerTime = ConsumerVal ($hash, $c2, "remainTime", "");                              # Restlaufzeit
          my $rpcurr       = ConsumerVal ($hash, $c2, "rpcurr",     "");                              # Readingname f. current Power
          
          if (!$rpcurr) {                                                                             # Workaround wenn Verbraucher ohne Leistungsmessung
              $currentPower = isConsumerPhysOn($hash, $c2) ? 'on' : 'off';
          }
          
          $ret       .= qq{<text class="flowg text" id="consumer-txt_$c2"     x="$pos_left" y="1090" style="text-anchor: start;">$currentPower</text>}      if ($flowgconPower);    # Current_Consumption Consumer
          $ret       .= qq{<text class="flowg text" id="consumer-txt_time_$c2"     x="$pos_left" y="1150" style="text-anchor: start;">$consumerTime</text>} if ($flowgconTime);     # Consumer Restlaufzeit                                                                                                                                                                                                    
          $pos_left  += ($consDist * 2);
      }
  }

  $ret .= qq{</g></svg>};
      
return $ret;
}

################################################################
#       prüfe ob Verbrauchericon + Farbe angegeben ist
#       und setze ggf. Ersatzwerte
#       $c     - Consumer Nummer
################################################################
sub substConsumerIcon {               
  my $hash = shift;
  my $c    = shift;
  
  my $name = $hash->{NAME};

  my $cicon   = ConsumerVal ($hash, $c, "icon",        "");                  # Icon des Consumerdevices angegeben ?
   
  if (!$cicon) {
      $cicon = 'light_light_dim_100'; 
  }
  
  my $color;
  ($cicon,$color) = split '@', $cicon;  
  
  if (!$color) {
      $color = isConsumerPhysOn($hash, $c) ? 'darkorange' : '';
  }
  
  $cicon .= '@'.$color if($color);
  
return $cicon;
}

################################################################
#                 Inject consumer icon
################################################################
sub consinject {
  my ($hash,$i,@consumers) = @_;
  my $name                 = $hash->{NAME};
  my $ret                  = "";

  for (@consumers) {
      if ($_) {
          my ($cons,$im,$start,$end) = split (':', $_);
          Log3 ($name, 4, "$name - Consumer to show -> $cons, relative to current time -> start: $start, end: $end") if($i<1); 
          
          if ($im && ($i >= $start) && ($i <= $end)) {
              $ret .= FW_makeImage($im);
         }
      }
  }
      
return $ret;
}

###############################################################################
#                            Balkenbreite normieren
#
# Die Balkenbreite wird bestimmt durch den Wert.
# Damit alle Balken die gleiche Breite bekommen, müssen die Werte auf 
# 6 Ausgabezeichen angeglichen werden.
# "align=center" gleicht gleicht es aus, alternativ könnte man sie auch 
# komplett rechtsbündig ausgeben.
# Es ergibt bei fast allen Styles gute Ergebnisse, Ausnahme IOS12 & 6, da diese 
# beiden Styles einen recht großen Font benutzen.
# Wird Wetter benutzt, wird die Balkenbreite durch das Icon bestimmt
#
###############################################################################
sub formatVal6 {
  my ($v,$kw,$w) = @_;
  my $n          = '&nbsp;';                                # positive Zahl

  if($v < 0) {
      $n = '-';                                             # negatives Vorzeichen merken
      $v = abs($v);
  }

  if($kw eq 'kWh') {                                        # bei Anzeige in kWh muss weniger aufgefüllt werden
      $v  = sprintf('%.1f',($v/1000));
      $v  += 0;                                             # keine 0.0 oder 6.0 etc

      return ($n eq '-') ? ($v*-1) : $v if defined($w) ;

      my $t = $v - int($v);                                 # Nachkommstelle ?

      if(!$t) {                                             # glatte Zahl ohne Nachkommastelle
          if(!$v) { 
              return '&nbsp;';                              # 0 nicht anzeigen, passt eigentlich immer bis auf einen Fall im Typ diff
          } 
          elsif ($v < 10) { 
              return '&nbsp;&nbsp;'.$n.$v.'&nbsp;&nbsp;'; 
          } 
          else { 
              return '&nbsp;&nbsp;'.$n.$v.'&nbsp;'; 
          }
      } 
      else {                                                # mit Nachkommastelle -> zwei Zeichen mehr .X
          if ($v < 10) { 
              return '&nbsp;'.$n.$v.'&nbsp;'; 
          } 
          else { 
              return $n.$v.'&nbsp;'; 
          }
      }
  }

  return ($n eq '-') ? ($v*-1) : $v if defined($w);

  # Werte bleiben in Watt
  if    (!$v)         { return '&nbsp;'; }                            ## no critic "Cascading" # keine Anzeige bei Null 
  elsif ($v <    10)  { return '&nbsp;&nbsp;'.$n.$v.'&nbsp;&nbsp;'; } # z.B. 0
  elsif ($v <   100)  { return '&nbsp;'.$n.$v.'&nbsp;&nbsp;'; }
  elsif ($v <  1000)  { return '&nbsp;'.$n.$v.'&nbsp;'; }
  elsif ($v < 10000)  { return  $n.$v.'&nbsp;'; }
  else                { return  $n.$v; }                              # mehr als 10.000 W :)
}

###############################################################################
#         Zuordungstabelle "WeatherId" angepasst auf FHEM Icons
###############################################################################
sub weather_icon {
  my $id = shift;

  $id      = int $id;
  my $lang = AttrVal ("global", "language", "EN");
  
  my $txt  = $lang eq "DE" ? "txtd" : "txte";
  
  if(defined $weather_ids{$id}) {
      return $weather_ids{$id}{icon}, encode("utf8", $weather_ids{$id}{$txt});
  }
  
return 'unknown','';
}

################################################################
#      benötigte Attribute im DWD Device checken
################################################################
sub checkdwdattr {
  my $name   = shift;
  my $dwddev = shift;
  my $amref  = shift;
  
  my @fcprop = map { trim($_) } split ",", AttrVal($dwddev, "forecastProperties", "pattern");
  my $fcr    = AttrVal($dwddev, "forecastResolution", 3);
  my $err;
  
  my @aneeded;
  for my $am (@$amref) {
      next if($am ~~ @fcprop);
      push @aneeded, $am;
  }
  
  if (@aneeded) {
      $err = qq{ERROR - device "$dwddev" -> attribute "forecastProperties" must contain: }.join ",",@aneeded;
  }
  
  if($fcr != 1) {
      $err .= ", " if($err);
      $err .= qq{ERROR - device "$dwddev" -> attribute "forecastResolution" must be set to "1"};
  }
  
  Log3 ($name, 2, "$name - $err") if($err);
  
return $err;
}

################################################################
#       ist Batterie installiert ?
#       1 - ja, 0 - nein
################################################################
sub useBattery {               
  my $name   = shift;

  my $badev  = ReadingsVal($name, "currentBatteryDev", "");                  # aktuelles Meter device für Batteriewerte
  my ($a,$h) = parseParams ($badev);
  $badev     = $a->[0] // "";
  return if(!$badev || !$defs{$badev});
  
return ($badev, $a ,$h);
}

################################################################
#       wird PV Autokorrektur verwendet ?
#       1 - ja, 0 - nein
################################################################
sub useAutoCorrection {               
  my $name = shift;

  my $dcauto = ReadingsVal ($name, 'pvCorrectionFactor_Auto', 'off');

  return 1 if($dcauto =~ /^on/xs);
  
return;
}

################################################################
#       Ist Attribut 'numHistDays' gesetzt ?
#       $usenhd: 1 - ja, 0 - nein
#       $nhd   : Anzahl der zu verwendenden HistDays
################################################################
sub useNumHistDays {               
  my $name = shift;

  my $usenhd = 0;
  my $nhd    = AttrVal($name, 'numHistDays', $calcmaxd+1);
  
  if($nhd == $calcmaxd+1) {
      $nhd = $calcmaxd;
  }
  else {
      $usenhd = 1;
  }
  
return ($usenhd, $nhd);
}

##################################################################################################
#            PV Forecast Rad1h in kWh / Wh
# Berechnung nach Formel 1 aus http://www.ing-büro-junge.de/html/photovoltaik.html:
#
#    * Faktor für Umwandlung kJ in kWh:   0.00027778
#    * Eigene Modulfläche in qm z.B.:     31,04
#    * Wirkungsgrad der Module in % z.B.: 16,52
#    * Wirkungsgrad WR in % z.B.:         98,3
#    * Korrekturwerte wegen Ausrichtung/Verschattung etc.
#
# Die Formel wäre dann: 
# Ertrag in Wh = Rad1h * 0.00027778 * 31,04 qm * 16,52% * 98,3% * 100% * 1000
#
# Berechnung nach Formel 2 aus http://www.ing-büro-junge.de/html/photovoltaik.html:
#
#    * Globalstrahlung:                G =  kJ / m2
#    * Korrektur mit Flächenfaktor f:  Gk = G * f
#    * Globalstrahlung (STC):          1 kW/m2
#    * Peak Leistung String (kWp):     Pnenn = x kW
#    * Performance Ratio:              PR (typisch 0,85 bis 0,9)
#    * weitere Korrekturwerte für Regen, Wolken etc.: Korr
#
#    pv (kWh) = G * f * 0.00027778 (kWh/m2) / 1 kW/m2 * Pnenn (kW) * PR * Korr
#    pv (Wh)  = G * f * 0.00027778 (kWh/m2) / 1 kW/m2 * Pnenn (kW) * PR * Korr * 1000
#
# Die Abhängigkeit der Strahlungsleistung der Sonnenenergie nach Wetterlage und Jahreszeit ist 
# hier beschrieben: 
# https://www.energie-experten.org/erneuerbare-energien/photovoltaik/planung/sonnenstunden
#
# !!! PV Berechnungsgrundlagen !!!
# https://www.energie-experten.org/erneuerbare-energien/photovoltaik/planung/ertrag
# http://www.ing-büro-junge.de/html/photovoltaik.html
# 
##################################################################################################
sub calcPVforecast {            
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $rad   = $paref->{rad};               # Nominale Strahlung aus DWD Device
  my $num   = $paref->{num};               # Nexthour 
  my $uac   = $paref->{uac};               # Nutze Autokorrektur (on/off)
  my $t     = $paref->{t};                 # aktueller Unix Timestamp
  my $fh    = $paref->{fh};
  my $fd    = $paref->{fd};
  
  my $type  = $hash->{TYPE};
  my $stch  = $data{$type}{$name}{strings};                                                           # String Configuration Hash
  my $pr    = 1.0;                                                                                    # Performance Ratio (PR)
  my $fh1   = $fh+1;
  
  my $chour      = strftime "%H", localtime($t+($num*3600));                                          # aktuelle Stunde
  my $reld       = $fd == 0 ? "today" : $fd == 1 ? "tomorrow" : "unknown";
  
  my $pvcorr     = ReadingsNum ($name, "pvCorrectionFactor_".sprintf("%02d",$fh+1), 1.00);            # PV Korrekturfaktor (auto oder manuell)
  my $hc         = $pvcorr;                                                                           # Voreinstellung RAW-Korrekturfaktor 
  my $hcfound    = "use manual correction factor";
  my $hq         = "m";
  
  my $clouddamp  = AttrVal($name, "cloudFactorDamping", $cldampdef);                                  # prozentuale Berücksichtigung des Bewölkungskorrekturfaktors
  my $raindamp   = AttrVal($name, "rainFactorDamping", $rdampdef);                                    # prozentuale Berücksichtigung des Regenkorrekturfaktors
  my @strings    = sort keys %{$stch};
  
  my $rainprob   = NexthoursVal ($hash, "NextHour".sprintf("%02d",$num), "rainprob", 0);              # Niederschlagswahrscheinlichkeit> 0,1 mm während der letzten Stunde
  my $rcf        = 1 - ((($rainprob - $rain_base)/100) * $raindamp/100);                              # Rain Correction Faktor mit Steilheit

  my $cloudcover = NexthoursVal ($hash, "NextHour".sprintf("%02d",$num), "cloudcover", 0);            # effektive Wolkendecke nächste Stunde X
  my $ccf        = 1 - ((($cloudcover - $cloud_base)/100) * $clouddamp/100);                          # Cloud Correction Faktor mit Steilheit und Fußpunkt
  
  my $range      = calcRange ($cloudcover);                                                           # V 0.50.1                                                           # Range errechnen

  ## Ermitteln des relevanten Autokorrekturfaktors
  if ($uac eq "on") {                                                                                 # Autokorrektur soll genutzt werden
      $hcfound   = "yes";                                                                             # Status ob Autokorrekturfaktor im Wertevorrat gefunden wurde         
      ($hc, $hq) = CircularAutokorrVal ($hash, sprintf("%02d",$fh+1), $range, undef);                 # Korrekturfaktor/KF-Qualität der Stunde des Tages der entsprechenden Bewölkungsrange
      $hq      //= 0;
      if (!defined $hc) {
          $hcfound = "no";
          $hc      = 1;                                                                               # keine Korrektur  
          $hq      = 0;
      }
  }
  
  $hc = sprintf "%.2f", $hc;

  $data{$type}{$name}{nexthours}{"NextHour".sprintf("%02d",$num)}{pvcorrf}    = $hc."/".$hq;
  $data{$type}{$name}{nexthours}{"NextHour".sprintf("%02d",$num)}{cloudrange} = $range;

  if($fd == 0 && $fh1) {
      $paref->{pvcorrf}  = $hc."/".$hq;
      $paref->{nhour}    = sprintf("%02d",$fh1);
      $paref->{histname} = "pvcorrfactor";
      setPVhistory ($paref);
      delete $paref->{histname};  
  }
  
  my $pvsum   = 0;      
  my $peaksum = 0; 
  my ($lh,$sq);                                                                                    
  
  for my $st (@strings) {                                                                             # für jeden String der Config ..
      my $peak   = $stch->{"$st"}{peak};                                                              # String Peak (kWp)
      $peak     *= 1000;                                                                              # kWp in Wp umrechnen
      my $ta     = $stch->{"$st"}{tilt};                                                              # Neigungswinkel Solarmodule
      my $moddir = $stch->{"$st"}{dir};                                                               # Ausrichtung der Solarmodule
      
      my $af     = $hff{$ta}{$moddir} / 100;                                                          # Flächenfaktor: http://www.ing-büro-junge.de/html/photovoltaik.html
      
      my $pv     = sprintf "%.1f", ($rad * $af * $kJtokWh * $peak * $pr * $ccf * $rcf);
  
      $lh = {                                                                                         # Log-Hash zur Ausgabe
          "moduleDirection"              => $moddir,
          "modulePeakString"             => $peak." W",
          "moduleTiltAngle"              => $ta,
          "Area factor"                  => $af,
          "Cloudcover"                   => $cloudcover,
          "CloudRange"                   => $range,
          "CloudFactorDamping"           => $clouddamp." %",
          "Cloudfactor"                  => $ccf,
          "Rainprob"                     => $rainprob,
          "Rainfactor"                   => $rcf,
          "RainFactorDamping"            => $raindamp." %",
          "Radiation"                    => $rad,
          "Factor kJ to kWh"             => $kJtokWh,
          "PV generation forecast (raw)" => $pv." Wh"
      };  
      
      $sq = q{};
      for my $idx (sort keys %{$lh}) {
          $sq .= $idx." => ".$lh->{$idx}."\n";             
      }

      Log3 ($name, 4, "$name - PV forecast calc (raw) for $reld Hour ".sprintf("%02d",$chour+1)." string $st ->\n$sq");
      
      $pvsum   += $pv;
      $peaksum += $peak;                                                                            
  }
  
  $data{$type}{$name}{current}{allstringspeak} = $peaksum;                                           # insgesamt installierte Peakleistung in W
  
  $pvsum *= $hc;                                                                                     # Korrekturfaktor anwenden
  $pvsum  = $peaksum if($pvsum > $peaksum);                                                          # Vorhersage nicht größer als die Summe aller PV-Strings Peak
      
  my $invcapacity = CurrentVal ($hash, "invertercapacity", 0);                                       # Max. Leistung des Invertrs
  
  if ($invcapacity && $pvsum > $invcapacity) {
      $pvsum = $invcapacity + ($invcapacity * 0.01);                                                 # PV Vorhersage auf WR Kapazität zzgl. 1% begrenzen
      Log3 ($name, 4, "$name - PV forecast limited to $pvsum Watt due to inverter capacity");
  }
      
  my $logao         = qq{};
  $paref->{pvsum}   = $pvsum;
  $paref->{peaksum} = $peaksum;
  ($pvsum, $logao)  = _70percentRule ($paref); 
  
  $lh = {                                                                                            # Log-Hash zur Ausgabe
      "CloudCorrFoundInStore"  => $hcfound,
      "PV correction factor"   => $hc,
      "PV correction quality"  => $hq,
      "PV generation forecast" => $pvsum." Wh ".$logao,
  };
  
  $sq = q{};
  for my $idx (sort keys %{$lh}) {
      $sq .= $idx." => ".$lh->{$idx}."\n";             
  }
  
  Log3 ($name, 4, "$name - PV forecast calc for $reld Hour ".sprintf("%02d",$chour+1)." summary: \n$sq");
 
return $pvsum;
}

################################################################
#                 70% Regel kalkulieren
################################################################
sub _70percentRule {
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $pvsum   = $paref->{pvsum};
  my $peaksum = $paref->{peaksum};
  my $num     = $paref->{num};                                                          # Nexthour 
  
  my $logao = qq{};
  my $confc = NexthoursVal ($hash, "NextHour".sprintf("%02d",$num), "confc", 0);
  my $max70 = $peaksum/100 * 70;
  
  if(AttrVal ($name, "follow70percentRule", "0") eq "1" && $pvsum > $max70) {      
      $pvsum = $max70;
      $logao = qq{(reduced by 70 percent rule)};
  }  

  if(AttrVal ($name, "follow70percentRule", "0") eq "dynamic" && $pvsum > $max70 + $confc) {
      $pvsum = $max70 + $confc;
      $logao = qq{(reduced by 70 percent dynamic rule)};
  }  
  
  $pvsum = int $pvsum;
 
return ($pvsum, $logao);
}

################################################################
#       Abweichung PVreal / PVforecast berechnen
#       bei eingeschalteter automat. Korrektur
################################################################
sub calcVariance {               
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $t     = $paref->{t};                                                              # aktuelle Unix-Zeit
  my $chour = $paref->{chour};
  my $day   = $paref->{day};                                                            # aktueller Tag (01,02,03...31)
   
  return if(!useAutoCorrection ($name));                                                # nur bei "on" automatische Varianzkalkulation
  
  my $idts = ReadingsTimestamp($name, "currentInverterDev", "");                        # Definitionstimestamp des Inverterdevice
  return if(!$idts);
  
  $idts = timestringToTimestamp ($idts);

  if($t - $idts < 7200) {
      my $rmh = sprintf "%.1f", ((7200 - ($t - $idts)) / 3600);
      Log3 ($name, 4, "$name - Variance calculation in standby. It starts in $rmh hours."); 
      readingsSingleUpdate($hash, "pvCorrectionFactor_Auto", "on (remains in standby for $rmh hours)", 0); 
      return;      
  }
  else {
      readingsSingleUpdate($hash, "pvCorrectionFactor_Auto", "on", 0);
  }

  my $maxvar = AttrVal($name, "maxVariancePerDay", $defmaxvar);                                           # max. Korrekturvarianz

  my @da;
  for my $h (1..23) {
      next if(!$chour || $h > $chour);
      
      my $fcval = ReadingsNum ($name, "Today_Hour".sprintf("%02d",$h)."_PVforecast", 0);
      next if(!$fcval);
 
      my $pvval = ReadingsNum ($name, "Today_Hour".sprintf("%02d",$h)."_PVreal", 0);
      next if(!$pvval);
      
      my $cdone = ReadingsVal ($name, "pvCorrectionFactor_".sprintf("%02d",$h)."_autocalc", "");
      if($cdone eq "done") {
          Log3 ($name, 5, "$name - pvCorrectionFactor Hour: ".sprintf("%02d",$h)." already calculated");
          next;
      }    
      
      Log3 ($name, 5, "$name - Hour: ".sprintf("%02d",$h).", Today PVreal: $pvval, PVforecast: $fcval");
            
      $paref->{hour}                  = $h;
      my ($pvhis,$fchis,$dnum,$range) = calcAvgFromHistory ($paref);                                      # historische PV / Forecast Vergleichswerte ermitteln
      
      my ($oldfac, $oldq) = CircularAutokorrVal ($hash, sprintf("%02d",$h), $range, 0);                   # bisher definierter Korrekturfaktor/KF-Qualität der Stunde des Tages der entsprechenden Bewölkungsrange      
      $oldfac             = 1 if(1*$oldfac == 0);
      
      my $factor;
      my ($usenhd) = useNumHistDays ($name);                                                              # ist Attr numHistDays gesetzt ?
    
      if($dnum) {                                                                                         # Werte in History vorhanden -> haben Prio !
          $dnum   = $dnum + 1;                                                                            
          $pvval  = ($pvval + $pvhis) / $dnum;                                                            # Ertrag aktuelle Stunde berücksichtigen
          $fcval  = ($fcval + $fchis) / $dnum;                                                            # Vorhersage aktuelle Stunde berücksichtigen
          $factor = sprintf "%.2f", ($pvval / $fcval);                                                    # Faktorberechnung: reale PV / Prognose
      }
      elsif($oldfac && !$usenhd) {                                                                        # keine Werte in History vorhanden, aber in CircularVal && keine Beschränkung durch Attr numHistDays
          $dnum   = $oldq + 1;
          $factor = sprintf "%.2f", ($pvval / $fcval);
          $factor = sprintf "%.2f", ($factor + $oldfac) / 2;
      }
      else {                                                                                              # ganz neuer Wert
          $factor = sprintf "%.2f", ($pvval / $fcval);
          $dnum   = 1;          
      }
      
      Log3 ($name, 4, "$name - variance -> range: $range, hour: $h, days: $dnum, real: $pvval, forecast: $fcval, factor: $factor");                                               
      
      if(abs($factor - $oldfac) > $maxvar) {
          $factor = sprintf "%.2f", ($factor > $oldfac ? $oldfac + $maxvar : $oldfac - $maxvar);
          Log3 ($name, 3, "$name - new limited Variance factor: $factor (old: $oldfac) for hour: $h");
      }
      else {
          Log3 ($name, 3, "$name - new Variance factor: $factor (old: $oldfac) for hour: $h calculated") if($factor != $oldfac);
      }
      
      if(defined $range) {
          my $type  = $hash->{TYPE};         
          Log3 ($name, 5, "$name - write correction factor into circular Hash: Factor $factor, Hour $h, Range $range");
          
          $data{$type}{$name}{circular}{sprintf("%02d",$h)}{pvcorrf}{$range} = $factor;                  # Korrekturfaktor für Bewölkung Range 0..10 für die jeweilige Stunde als Datenquelle eintragen
          $data{$type}{$name}{circular}{sprintf("%02d",$h)}{quality}{$range} = $dnum;                    # Korrekturfaktor Qualität
      }
      else {
          $range = "";
      }
      
      push @da, "pvCorrectionFactor_".sprintf("%02d",$h)."<>".$factor." (automatic - old factor: $oldfac, cloudiness range: $range, days in range: $dnum)";
      push @da, "pvCorrectionFactor_".sprintf("%02d",$h)."_autocalc<>done";    
  }
  
  createReadingsFromArray ($hash, \@da, 1);
      
return;
}

################################################################
#   Berechne Durchschnitte PV Vorhersage / PV Ertrag 
#   aus Werten der PV History
################################################################
sub calcAvgFromHistory {               
  my $paref = shift;
  my $hash  = $paref->{hash};         
  my $hour  = $paref->{hour};                                                             # Stunde des Tages für die der Durchschnitt bestimmt werden soll
  my $day   = $paref->{day};                                                              # aktueller Tag
  
  $hour     = sprintf("%02d",$hour);
  
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};  
  my $pvhh  = $data{$type}{$name}{pvhist};
  
  my ($usenhd, $calcd) = useNumHistDays ($name);                                          # ist Attr numHistDays gesetzt ? und welcher Wert

  my @k     = sort {$a<=>$b} keys %{$pvhh};
  my $ile   = $#k;                                                                        # Index letztes Arrayelement
  my ($idx) = grep {$k[$_] eq "$day"} (0..@k-1);                                          # Index des aktuellen Tages
  
  if(defined $idx) {
      my $ei = $idx-1;
      $ei    = $ei < 0 ? $ile : $ei;
      my @efa;
      
      for my $e (0..$calcmaxd) {
          last if($e == $calcmaxd || $k[$ei] == $day);
          unshift @efa, $k[$ei];
          $ei--;
      }
      
      my $chwcc = HistoryVal ($hash, $day, $hour, "wcc", undef);                           # Wolkenbedeckung Heute & abgefragte Stunde
      
      if(!defined $chwcc) {
          Log3 ($name, 4, "$name - Day $day has no cloudiness value set for hour $hour, no past averages can be calculated."); 
          return;
      }
           
      my $range = calcRange ($chwcc);                                                      # V 0.50.1  
      
      if(scalar(@efa)) {
          Log3 ($name, 4, "$name - PV History -> Raw Days ($calcmaxd) for average check: ".join " ",@efa); 
      }
      else {                                                                               # vermeide Fehler: Illegal division by zero
          Log3 ($name, 4, "$name - PV History -> Day $day has index $idx. Use only current day for average calc");
          return (undef,undef,undef,$range);
      }     
      
      Log3 ($name, 4, "$name - cloudiness range of day/hour $day/$hour is: $range");
      
      my $dnum         = 0;      
      my ($pvrl,$pvfc) = (0,0);
            
      for my $dayfa (@efa) {
          my $histwcc = HistoryVal ($hash, $dayfa, $hour, "wcc", undef);                   # historische Wolkenbedeckung
          
          if(!defined $histwcc) {
              Log3 ($name, 4, "$name - PV History -> Day $dayfa has no cloudiness value set for hour $hour, this history dataset is ignored."); 
              next;
          }  
        
          $histwcc = calcRange ($histwcc);                                                 # V 0.50.1         

          if($range == $histwcc) {               
              $pvrl  += HistoryVal ($hash, $dayfa, $hour, "pvrl", 0);
              $pvfc  += HistoryVal ($hash, $dayfa, $hour, "pvfc", 0);
              $dnum++;
              Log3 ($name, 5, "$name - PV History -> historical Day/hour $dayfa/$hour included - cloudiness range: $range");
              last if( $dnum == $calcd);
          }
          else {
              Log3 ($name, 5, "$name - PV History -> current/historical cloudiness range different: $range/$histwcc Day/hour $dayfa/$hour discarded.");
          }
      }
      
      if(!$dnum) {
          Log3 ($name, 5, "$name - PV History -> all cloudiness ranges were different/not set -> no historical averages calculated");
          return (undef,undef,undef,$range);
      }
      
      my $pvhis = sprintf "%.2f", $pvrl;
      my $fchis = sprintf "%.2f", $pvfc;
      
      Log3 ($name, 5, "$name - PV History -> Summary - cloudiness range: $range, days: $dnum, pvHist:$pvhis, fcHist:$fchis");
      
      return ($pvhis,$fchis,$dnum,$range);
  }
  
return;
}

################################################################
#            Bewölkungs- bzw. Regenrange berechnen
################################################################
sub calcRange {
  my $range = shift;
  
  $range = sprintf("%.0f", $range/10); 

return $range;
}

################################################################
#   PV und PV Forecast in History-Hash speichern zur 
#   Berechnung des Korrekturfaktors über mehrere Tage
################################################################
sub setPVhistory {               
  my $paref          = shift;
  my $hash           = $paref->{hash};
  my $name           = $paref->{name};
  my $t              = $paref->{t};                                        # aktuelle Unix-Zeit
  my $nhour          = $paref->{nhour};
  my $day            = $paref->{day};
  my $dayname        = $paref->{dayname};                                  # aktueller Wochentagsname
  my $histname       = $paref->{histname}      // qq{};
  my $ethishour      = $paref->{ethishour}     // 0;
  my $etotal         = $paref->{etotal};
  my $batinthishour  = $paref->{batinthishour};                            # Batterieladung in Stunde
  my $btotin         = $paref->{batintotal};                               # totale Batterieladung
  my $batoutthishour = $paref->{batoutthishour};                           # Batterieentladung in Stunde
  my $btotout        = $paref->{batouttotal};                              # totale Batterieentladung  
  my $calcpv         = $paref->{calcpv}        // 0;
  my $gcthishour     = $paref->{gctotthishour} // 0;                       # Netzbezug
  my $fithishour     = $paref->{gftotthishour} // 0;                       # Netzeinspeisung
  my $con            = $paref->{con}           // 0;                       # realer Hausverbrauch Energie
  my $confc          = $paref->{confc}         // 0;                       # Verbrauchsvorhersage        
  my $consumerco     = $paref->{consumerco};                               # Verbrauch eines Verbrauchers
  my $wid            = $paref->{wid}           // -1;
  my $wcc            = $paref->{wcc}           // 0;                       # Wolkenbedeckung
  my $wrp            = $paref->{wrp}           // 0;                       # Wahrscheinlichkeit von Niederschlag
  my $pvcorrf        = $paref->{pvcorrf}       // "1.00/0";                # pvCorrectionFactor
  my $temp           = $paref->{temp};                                     # Außentemperatur
  my $val            = $paref->{val}           // qq{};                    # Wert zur Speicherung in pvHistory (soll mal generell verwendet werden -> Change)
  
  my $type = $hash->{TYPE};
  
  $data{$type}{$name}{pvhist}{$day}{99}{dayname} = $dayname; 

  if($histname eq "batinthishour") {                                                              # Batterieladung
      $val = $batinthishour;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{batin} = $batinthishour;  
      
      my $batinsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $batinsum += HistoryVal ($hash, $day, $k, "batin", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{batin} = $batinsum;      
  }
  
  if($histname eq "batoutthishour") {                                                             # Batterieentladung
      $val = $batoutthishour;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{batout} = $batoutthishour;  
      
      my $batoutsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $batoutsum += HistoryVal ($hash, $day, $k, "batout", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{batout} = $batoutsum;      
  }
  
  if($histname eq "pvrl") {                                                                       # realer Energieertrag
      $val = $ethishour;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{pvrl} = $ethishour;  
      
      my $pvrlsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $pvrlsum += HistoryVal ($hash, $day, $k, "pvrl", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{pvrl} = $pvrlsum;      
  }
  
  if($histname eq "pvfc") {                                                                       # prognostizierter Energieertrag
      $val = $calcpv;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{pvfc} = $calcpv; 

      my $pvfcsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $pvfcsum += HistoryVal ($hash, $day, $k, "pvfc", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{pvfc} = $pvfcsum;       
  }
  
  if($histname eq "confc") {                                                                       # prognostizierter Hausverbrauch
      $val = $confc;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{confc} = $confc; 

      my $confcsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $confcsum += HistoryVal ($hash, $day, $k, "confc", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{confc} = $confcsum;       
  } 
  
  if($histname eq "cons") {                                                                       # bezogene Energie
      $val = $gcthishour;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{gcons} = $gcthishour; 

      my $gcsum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $gcsum += HistoryVal ($hash, $day, $k, "gcons", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{gcons} = $gcsum;       
  }
  
  if($histname eq "gfeedin") {                                                                    # eingespeiste Energie
      $val = $fithishour;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{gfeedin} = $fithishour; 

      my $gfisum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $gfisum += HistoryVal ($hash, $day, $k, "gfeedin", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{gfeedin} = $gfisum;       
  }
  
  if($histname eq "con") {                                                                       # Energieverbrauch des Hauses
      $val = $con;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{con} = $con; 

      my $consum = 0;
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          $consum += HistoryVal ($hash, $day, $k, "con", 0);
      }
      $data{$type}{$name}{pvhist}{$day}{99}{con} = $consum;       
  }
  
  if($histname =~ /csm[et][0-9]+$/xs) {                                                          # Verbrauch eines Verbrauchers
      $val = $consumerco;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{$histname} = $consumerco;  

      if($histname =~ /csme[0-9]+$/xs) {
          my $sum = 0;
          
          for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
              next if($k eq "99");
              my $csme = HistoryVal ($hash, $day, $k, "$histname", 0);
              next if(!$csme);
              
              $sum += $csme;
          }
          
          $data{$type}{$name}{pvhist}{$day}{99}{$histname} = $sum;        
      }      
  }
  
  if($histname =~ /cyclescsm[0-9]+$/xs) {                                                         # Anzahl Tageszyklen des Verbrauchers
      $data{$type}{$name}{pvhist}{$day}{99}{$histname} = $val;        
  }
  
  if($histname =~ /minutescsm[0-9]+$/xs) {                                                         # Anzahl Aktivminuten des Verbrauchers
      $data{$type}{$name}{pvhist}{$day}{$nhour}{$histname} = $val;
      my $minutes = 0;
      my $num     = substr ($histname,10,2);
      
      for my $k (keys %{$data{$type}{$name}{pvhist}{$day}}) {
          next if($k eq "99");
          my $csmm = HistoryVal ($hash, $day, $k, "$histname", 0);
          next if(!$csmm);
          
          $minutes += $csmm;
      }
      
      my $cycles = HistoryVal ($hash, $day, 99, "cyclescsm${num}", 0);
      $data{$type}{$name}{pvhist}{$day}{99}{"hourscsme${num}"} = ceil ($minutes / $cycles / 60 ) if($cycles);       
  }
  
  if($histname eq "etotal") {                                                                     # etotal des Wechselrichters
      $val = $etotal;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{etotal} = $etotal;
      $data{$type}{$name}{pvhist}{$day}{99}{etotal}     = q{};      
  }
  
  if($histname eq "batintotal") {                                                                 # totale Batterieladung
      $val = $btotin;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{batintotal} = $btotin;
      $data{$type}{$name}{pvhist}{$day}{99}{batintotal}     = q{};      
  }
  
  if($histname eq "batouttotal") {                                                                # totale Batterieentladung
      $val = $btotout;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{batouttotal} = $btotout;
      $data{$type}{$name}{pvhist}{$day}{99}{batouttotal}     = q{};      
  }
  
  if($histname eq "weatherid") {                                                                  # Wetter ID
      $val = $wid;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{weatherid} = $wid;
      $data{$type}{$name}{pvhist}{$day}{99}{weatherid}     = q{};      
  }
  
  if($histname eq "weathercloudcover") {                                                          # Wolkenbedeckung
      $val = $wcc;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{wcc} = $wcc; 
      $data{$type}{$name}{pvhist}{$day}{99}{wcc}     = q{};       
  }
  
  if($histname eq "weatherrainprob") {                                                            # Niederschlagswahrscheinlichkeit
      $val = $wrp;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{wrp} = $wrp; 
      $data{$type}{$name}{pvhist}{$day}{99}{wrp}     = q{};       
  }
  
  if($histname eq "pvcorrfactor") {                                                               # pvCorrectionFactor
      $val = $pvcorrf;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{pvcorrf} = $pvcorrf; 
      $data{$type}{$name}{pvhist}{$day}{99}{pvcorrf}     = q{};      
  }
  
  if($histname eq "temperature") {                                                                # Außentemperatur
      $val = $temp;
      $data{$type}{$name}{pvhist}{$day}{$nhour}{temp} = $temp; 
      $data{$type}{$name}{pvhist}{$day}{99}{temp}     = q{};      
  }
  
  Log3 ($name, 5, "$name - set PV History day: $day, hour: $nhour, hash: $histname, val: $val");
    
return;
}

################################################################
#           liefert aktuelle Einträge des in $htol
#           angegebenen internen Hash
################################################################
sub listDataPool {                 
  my $hash = shift;
  my $htol = shift;  
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
  my ($sq,$h);
  
  my $sub = sub { 
      my $day = shift;
      my $ret;          
      for my $key (sort{$a<=>$b} keys %{$h->{$day}}) {
          my $pvrl    = HistoryVal ($hash, $day, $key, "pvrl",        "-");
          my $pvfc    = HistoryVal ($hash, $day, $key, "pvfc",        "-");
          my $gcon    = HistoryVal ($hash, $day, $key, "gcons",       "-");
          my $con     = HistoryVal ($hash, $day, $key, "con",         "-");
          my $confc   = HistoryVal ($hash, $day, $key, "confc",       "-");
          my $gfeedin = HistoryVal ($hash, $day, $key, "gfeedin",     "-");
          my $wid     = HistoryVal ($hash, $day, $key, "weatherid",   "-");
          my $wcc     = HistoryVal ($hash, $day, $key, "wcc",         "-");
          my $wrp     = HistoryVal ($hash, $day, $key, "wrp",         "-");
          my $temp    = HistoryVal ($hash, $day, $key, "temp",      undef);
          my $pvcorrf = HistoryVal ($hash, $day, $key, "pvcorrf",     "-");
          my $dayname = HistoryVal ($hash, $day, $key, "dayname",   undef);
          my $etotal  = HistoryVal ($hash, $day, $key, "etotal",      "-");
          my $btotin  = HistoryVal ($hash, $day, $key, "batintotal",  "-");
          my $batin   = HistoryVal ($hash, $day, $key, "batin",       "-");
          my $btotout = HistoryVal ($hash, $day, $key, "batouttotal", "-");
          my $batout  = HistoryVal ($hash, $day, $key, "batout",      "-");
          
          $ret .= "\n      " if($ret);
          $ret .= $key." => etotal: $etotal, pvfc: $pvfc, pvrl: $pvrl"; 
          $ret .= "\n            ";
          $ret .= "confc: $confc, con: $con, gcon: $gcon, gfeedin: $gfeedin";
          $ret .= "\n            ";
          $ret .= "batintotal: $btotin, batin: $batin, batouttotal: $btotout, batout: $batout";
          $ret .= "\n            ";
          $ret .= "wid: $wid";
          $ret .= ", wcc: $wcc";
          $ret .= ", wrp: $wrp";
          $ret .= ", temp: $temp"       if($temp);
          $ret .= ", pvcorrf: $pvcorrf";
          $ret .= ", dayname: $dayname" if($dayname);
          
          my $csm;
          for my $c (1..$maxconsumer) {
              $c        = sprintf "%02d", $c;
              my $nl    = 0;
              my $csmc  = HistoryVal ($hash, $day, $key, "cyclescsm${c}",  undef);
              my $csmt  = HistoryVal ($hash, $day, $key, "csmt${c}",       undef);
              my $csme  = HistoryVal ($hash, $day, $key, "csme${c}",       undef);
              my $csmm  = HistoryVal ($hash, $day, $key, "minutescsm${c}", undef);
              my $csmh  = HistoryVal ($hash, $day, $key, "hourscsme${c}",  undef);
              
              if(defined $csmc) {
                  $csm .= "cyclescsm${c}: $csmc";
                  $nl   = 1;
              }
              
              if(defined $csmt) {
                  $csm .= ", " if($nl);
                  $csm .= "csmt${c}: $csmt";
                  $nl   = 1;
              }
              
              if(defined $csme) {
                  $csm .= ", " if($nl);
                  $csm .= "csme${c}: $csme";
                  $nl   = 1;
              }
              
              if(defined $csmm) {
                  $csm .= ", " if($nl);
                  $csm .= "minutescsm${c}: $csmm";
                  $nl   = 1;
              }
              
              if(defined $csmh) {
                  $csm .= ", " if($nl);
                  $csm .= "hourscsme${c}: $csmh";
                  $nl   = 1;
              }
              
              $csm .= "\n            " if($nl);
          }
          
          if($csm) {
              $ret .= "\n            ";
              $ret .= $csm;
          }
      }
      return $ret;
  };
  
  if ($htol eq "pvhist") {
      $h = $data{$type}{$name}{pvhist};
      if (!keys %{$h}) {
          return qq{PV cache is empty.};
      }
      for my $idx (sort{$a<=>$b} keys %{$h}) {
          $sq .= $idx." => ".$sub->($idx)."\n";             
      }
  }
  
  if ($htol eq "consumer") {
      $h = $data{$type}{$name}{consumers};
      if (!keys %{$h}) {
          return qq{Consumer cache is empty.};
      }
      for my $i (keys %{$h}) {
          if ($i !~ /^[0-9]{2}$/ix) {                                   # bereinigen ungültige consumer, Forum: https://forum.fhem.de/index.php/topic,117864.msg1173219.html#msg1173219
              delete $data{$type}{$name}{consumers}{$i};
              Log3 ($name, 3, qq{$name - INFO - invalid consumer key "$i" was deleted from consumer Hash});
          }         
      }
      
      for my $idx (sort{$a<=>$b} keys %{$h}) {
          my $cret;
          for my $ckey (sort keys %{$h->{$idx}}) {
              if(ref $h->{$idx}{$ckey} eq "HASH") {
                  my $hk;
                  for my $f (sort {$a<=>$b} keys %{$h->{$idx}{$ckey}}) {
                      $hk .= " " if($hk);
                      $hk .= "$f=".$h->{$idx}{$ckey}{$f};
                  }
                  $cret .= $ckey." => ".$hk."\n      ";
              }
              else {
                  $cret .= $ckey." => ".ConsumerVal ($hash, $idx, $ckey, "")."\n      ";
              }
          }

          $sq .= $idx." => ".$cret."\n";             
      }
  }  
  
  if ($htol eq "circular") {
      $h = $data{$type}{$name}{circular};
      if (!keys %{$h}) {
          return qq{Circular cache is empty.};
      }
      for my $idx (sort keys %{$h}) {
          my $pvfc    = CircularVal ($hash, $idx, "pvfc",       "-");
          my $pvrl    = CircularVal ($hash, $idx, "pvrl",       "-");
          my $confc   = CircularVal ($hash, $idx, "confc",      "-");
          my $gcons   = CircularVal ($hash, $idx, "gcons",      "-");
          my $gfeedin = CircularVal ($hash, $idx, "gfeedin",    "-");
          my $wid     = CircularVal ($hash, $idx, "weatherid",  "-");
          my $wtxt    = CircularVal ($hash, $idx, "weathertxt", "-");
          my $wccv    = CircularVal ($hash, $idx, "wcc",        "-");
          my $wrprb   = CircularVal ($hash, $idx, "wrp",        "-");
          my $temp    = CircularVal ($hash, $idx, "temp",       "-");
          my $pvcorrf = CircularVal ($hash, $idx, "pvcorrf",    "-");
          my $quality = CircularVal ($hash, $idx, "quality",    "-");
          my $batin   = CircularVal ($hash, $idx, "batin",      "-");
          my $batout  = CircularVal ($hash, $idx, "batout",     "-");
          
          my $pvcf;
          if(ref $pvcorrf eq "HASH") {
              for my $f (sort {$a<=>$b} keys %{$h->{$idx}{pvcorrf}}) {
                  $pvcf .= " " if($pvcf);
                  $pvcf .= "$f=".$h->{$idx}{pvcorrf}{$f};
              }
          }
          else {
              $pvcf = $pvcorrf;
          }
          
          my $cfq;
          if(ref $quality eq "HASH") {
              for my $q (sort {$a<=>$b} keys %{$h->{$idx}{quality}}) {
                  $cfq .= " " if($cfq);
                  $cfq .= "$q=".$h->{$idx}{quality}{$q};
              }
          }
          else {
              $cfq = $quality;
          }
          
          $sq .= "\n" if($sq);
          $sq .= $idx." => pvfc: $pvfc, pvrl: $pvrl, batin: $batin, batout: $batout\n";
          $sq .= "      confc: $confc, gcon: $gcons, gfeedin: $gfeedin, wcc: $wccv, wrp: $wrprb\n";
          $sq .= "      temp: $temp, wid: $wid, wtxt: $wtxt\n";
          $sq .= "      corr: $pvcf\n";
          $sq .= "      quality: $cfq";
      }
  }
  
  if ($htol eq "nexthours") {
      $h = $data{$type}{$name}{nexthours};
      if (!keys %{$h}) {
          return qq{NextHours cache is empty.};
      }
      for my $idx (sort keys %{$h}) {
          my $nhts    = NexthoursVal ($hash, $idx, "starttime",  "-");
          my $hod     = NexthoursVal ($hash, $idx, "hourofday",  "-");
          my $today   = NexthoursVal ($hash, $idx, "today",      "-");
          my $pvfc    = NexthoursVal ($hash, $idx, "pvforecast", "-");
          my $wid     = NexthoursVal ($hash, $idx, "weatherid",  "-");
          my $neff    = NexthoursVal ($hash, $idx, "cloudcover", "-");
          my $crange  = NexthoursVal ($hash, $idx, "cloudrange", "-");
          my $r101    = NexthoursVal ($hash, $idx, "rainprob",   "-");
          my $rad1h   = NexthoursVal ($hash, $idx, "Rad1h",      "-");
          my $pvcorrf = NexthoursVal ($hash, $idx, "pvcorrf",    "-");
          my $temp    = NexthoursVal ($hash, $idx, "temp",       "-");
          my $confc   = NexthoursVal ($hash, $idx, "confc",      "-");
          $sq        .= "\n" if($sq);
          $sq        .= $idx." => starttime: $nhts, hourofday: $hod, today: $today\n";
          $sq        .= "              pvfc: $pvfc, confc: $confc, Rad1h: $rad1h\n";
          $sq        .= "              wid: $wid, wcc: $neff, wrp: $r101, temp=$temp\n";
          $sq        .= "              crange: $crange, correff: $pvcorrf";
      }
  }
  
  if ($htol eq "qualities") {
      $h = $data{$type}{$name}{nexthours};
      if (!keys %{$h}) {
          return qq{NextHours cache is empty.};
      }
      for my $idx (sort keys %{$h}) {
          my $nhfc    = NexthoursVal ($hash, $idx, "pvforecast", undef);
          next if(!$nhfc);
          my $nhts    = NexthoursVal ($hash, $idx, "starttime",  undef);
          my $neff    = NexthoursVal ($hash, $idx, "cloudcover",   "-");
          my $crange  = NexthoursVal ($hash, $idx, "cloudrange",   "-");
          my $pvcorrf = NexthoursVal ($hash, $idx, "pvcorrf",    "-/-");
          my ($f,$q)  = split "/", $pvcorrf;
          $sq        .= "\n" if($sq);
          $sq        .= "starttime: $nhts, wcc: $neff, crange: $crange, quality: $q, used factor: $f";
      }
  }
  
  if ($htol eq "current") {
      $h = $data{$type}{$name}{current};
      if (!keys %{$h}) {
          return qq{Current values cache is empty.};
      }
      for my $idx (sort keys %{$h}) {
          if (ref $h->{$idx} ne "ARRAY") {
              $sq .= $idx." => ".$h->{$idx}."\n";  
          }
          else {
             my $aser = join " ",@{$h->{$idx}};
             $sq .= $idx." => ".$aser."\n";               
          }     
      }
  }
      
return $sq;
}

################################################################
#        liefert aktuelle Stringkonfiguration
#        inkl. Vollständigkeitscheck
################################################################
sub checkStringConfig {                 
  my $hash = shift;
  
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $stch = $data{$type}{$name}{strings};
  my $lang = AttrVal ("global", 'language', 'EN');
  
  my $sub = sub { 
      my $string = shift;
      my $ret;          
      for my $key (sort keys %{$stch->{"$string"}}) {
          $ret    .= ", " if($ret);
          $ret    .= $key.": ".$stch->{"$string"}{$key};
      }
      return $ret;
  };
        
  if (!keys %{$stch}) {
      return qq{String configuration is empty.};
  }
  
  my $sc;
  my $cf = 0;
  for my $sn (sort keys %{$stch}) {
      my $sp = $sn." => ".$sub->($sn)."<br>";
      $cf    = 1 if($sp !~ /dir.*?peak.*?tilt/x);             # Test Vollständigkeit: z.B. Süddach => dir: S, peak: 5.13, tilt: 45
      $sc   .= $sp;
  }
  
  if($cf) {                             
      $sc .= "<br><br>".encode ("utf8", $hqtxt{strnok}{$lang});
  }
  else {
      $sc .= "<br><br>".encode ("utf8", $hqtxt{strok}{$lang});
  }
      
return $sc;
}

################################################################
#  Array auf eine festgelegte Anzahl Elemente beschränken,
#  Das älteste Element wird entfernt
#
#  $href  = Referenz zum Array
#  $limit = die Anzahl Elemente auf die gekürzt werden soll
#           (default 3)
#
################################################################
sub limitArray {
  my $href  = shift;
  my $limit = shift // 3;  
  
  return if(ref $href ne "ARRAY");
  
  while (scalar @{$href} > $limit) {
      shift @{$href};
  }

return;
}

################################################################
#              Timestrings berechnen
################################################################
sub timestampToTimestring {
  my $epoch = shift;
  
  my ($lyear,$lmonth,$lday,$lhour,$lmin,$lsec) = (localtime($epoch))[5,4,3,2,1,0];
  my $ts;
  
  $lyear += 1900;                                                                             # year is 1900 based
  $lmonth++;                                                                                  # month number is zero based
  
  my ($sec,$min,$hour,$day,$mon,$year) = (localtime(time))[0,1,2,3,4,5];                      # Standard f. z.B. Readingstimstamp
  $year += 1900;                                                                            
  $mon++;  
  my $realts = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year,$mon,$day,$hour,$min,$sec);
  my $tsdef  = sprintf("%04d-%02d-%02d %02d:%s", $lyear,$lmonth,$lday,$lhour,"00:00");             # engl. Variante für Logging-Timestamps etc. (Minute/Sekunde == 00)
  my $tsfull = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $lyear,$lmonth,$lday,$lhour,$lmin,$lsec);  # engl. Variante Vollzeit
  
  if(AttrVal("global","language","EN") eq "DE") {
      $ts = sprintf("%02d.%02d.%04d %02d:%s", $lday,$lmonth,$lyear,$lhour,"00:00");
  } 
  else {
      $ts = $tsdef;
  }
  
return ($ts,$tsdef,$realts,$tsfull);
}

################################################################
#  einen Zeitstring YYYY-MM-TT hh:mm:ss in einen Unix 
#  Timestamp umwandeln
################################################################
sub timestringToTimestamp {            
  my $tstring = shift;

  my($y, $mo, $d, $h, $m, $s) = $tstring =~ /([0-9]{4})-([0-9]{2})-([0-9]{2})\s([0-9]{2}):([0-9]{2}):([0-9]{2})/xs;
  return if(!$mo || !$y);
  
  my $timestamp = fhemTimeLocal($s, $m, $h, $d, $mo-1, $y-1900);
  
return $timestamp;
}

################################################################
#                   Readings aus Array erstellen
#       $daref:  Referenz zum Array der zu erstellenden Readings
#                muß Paare <Readingname>:<Wert> enthalten
#       $doevt:  1-Events erstellen, 0-keine Events erstellen
#
# readingsBulkUpdate($hash,$reading,$value,$changed,$timestamp)
#
################################################################
sub createReadingsFromArray {
  my $hash  = shift;
  my $daref = shift;
  my $doevt = shift // 0;  
  
  readingsBeginUpdate($hash);
  
  for my $elem (@$daref) {
      my ($rn,$rval,$ts) = split "<>", $elem, 3;
      readingsBulkUpdate($hash, $rn, $rval, undef, $ts);      
  }

  readingsEndUpdate($hash, $doevt);
  
return;
}

################################################################
#    alle Readings eines Devices oder nur Reading-Regex 
#    löschen
################################################################
sub deleteReadingspec {
  my $hash = shift;
  my $spec = shift // ".*";
  
  my $readingspec = '^'.$spec.'$';
  
  for my $reading ( grep { /$readingspec/x } keys %{$hash->{READINGS}} ) {
      readingsDelete($hash, $reading);
  }
  
return;
}

######################################################################################
#                   NOTIFYDEV erstellen
######################################################################################
sub createNotifyDev {
  my $hash = shift;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
  RemoveInternalTimer($hash, "FHEM::SolarForecast::createNotifyDev");
  
  if($init_done == 1) {
      my @nd;
      my ($afc,$ara,$ain,$ame,$aba,$h);
      
      my $fcdev = ReadingsVal($name, "currentForecastDev",  "");             # Weather forecast Device
      ($afc,$h) = parseParams ($fcdev);
      $fcdev    = $afc->[0] // "";      
      
      my $radev = ReadingsVal($name, "currentRadiationDev", "");             # Radiation forecast Device
      ($ara,$h) = parseParams ($radev);
      $radev    = $ara->[0] // "";
      
      my $indev = ReadingsVal($name, "currentInverterDev",  "");             # Inverter Device
      ($ain,$h) = parseParams ($indev);
      $indev    = $ain->[0] // "";
      
      my $medev = ReadingsVal($name, "currentMeterDev",     "");             # Meter Device
      ($ame,$h) = parseParams ($medev);
      $medev    = $ame->[0] // "";
      
      my $badev = ReadingsVal($name, "currentBatteryDev",   "");             # Battery Device
      ($aba,$h) = parseParams ($badev);
      $badev    = $aba->[0] // "";
                                                  
      for my $c (sort{$a<=>$b} keys %{$data{$type}{$name}{consumers}}) {     # Consumer Devices
          my $codev    = AttrVal($name, "consumer${c}", "");                            
          my ($ac,$hc) = parseParams ($codev);
          $codev       = $ac->[0] // ""; 
          
          push @nd, $codev if($codev);       
      }
      
      push @nd, $fcdev;
      push @nd, $radev if($radev ne $fcdev);
      push @nd, $indev;
      push @nd, $medev;
      push @nd, $badev;
      
      if(@nd) {
          $hash->{NOTIFYDEV} = join ",", @nd;
          readingsSingleUpdate ($hash, ".associatedWith", join(" ",@nd), 0);
      }
  } 
  else {
      InternalTimer(gettimeofday()+3, "FHEM::SolarForecast::createNotifyDev", $hash, 0);
  }
  
return;
}

################################################################
#   Planungsdaten Consumer löschen
#   $c - Consumer Nummer
################################################################
sub deleteConsumerPlanning {
  my $hash = shift;
  my $c    = shift;  
  
  my $type = $hash->{TYPE};
  my $name = $hash->{NAME};
  
  delete $data{$type}{$name}{consumers}{$c}{planstate};
  delete $data{$type}{$name}{consumers}{$c}{planswitchon};
  delete $data{$type}{$name}{consumers}{$c}{planswitchoff};
  
  # $data{$type}{$name}{consumers}{$c}{isIntimeframe} = 0;
  
  deleteReadingspec ($hash, "consumer${c}.*" );

return;
}

################################################################
#  Funktion liefert 1 wenn Consumer physisch "eingeschaltet"
#  ist, d.h. der Wert onreg des Readings rswstate wahr ist 
################################################################
sub isConsumerPhysOn {
  my $hash = shift;
  my $c    = shift;
  my $name = $hash->{NAME};  
  
  my $cname = ConsumerVal ($hash, $c, "name", "");                       # Devicename Customer

  if(!$defs{$cname}) {
      Log3($name, 1, qq{$name - the consumer device "$cname" is invalid, the "on" state can't be identified});
      return;
  }
  
  my $reg      = ConsumerVal ($hash, $c, "onreg",    "on"); 
  my $rswstate = ConsumerVal ($hash, $c, "rswstate", "state");           # Reading mit Schaltstatus
  my $swstate  = ReadingsVal ($cname, $rswstate,     "undef");
  
  if ($swstate =~ m/^$reg$/x) {                                                     
      return 1;
  }

return;
}

################################################################
#  Funktion liefert 1 wenn Consumer physisch "ausngeschaltet"
#  ist, d.h. der Wert offreg des Readings rswstate wahr ist 
################################################################
sub isConsumerPhysOff {
  my $hash = shift;
  my $c    = shift;  
  my $name = $hash->{NAME};
  
  my $cname = ConsumerVal ($hash, $c, "name", "");                       # Devicename Customer

  if(!$defs{$cname}) {
      Log3($name, 1, qq{$name - the consumer device "$cname" is invalid, the "off" state can't be identified});
      return;
  }
  
  my $reg      = ConsumerVal ($hash, $c, "offreg",     "off");
  my $rswstate = ConsumerVal ($hash, $c, "rswstate", "state");           # Reading mit Schaltstatus  
  my $swstate  = ReadingsVal ($cname, $rswstate,     "undef");
  
  if ($swstate =~ m/^$reg$/x) {                                                     
      return 1;
  }

return;
}

################################################################
#  Funktion liefert "1" wenn die zusätzliche Einschaltbedingung
#  aus dem Schlüssel "swoncond" im Consumer Attribut wahr ist
#
#  $info - den Info-Status
#  $err  - einen Error-Status
#
################################################################
sub isAddSwitchOnCond {
  my $hash = shift;
  my $c    = shift;

  my $info = q{};
  my $err  = q{};
  
  my $dswoncond = ConsumerVal ($hash, $c, "dswoncond", "");                     # Device zur Lieferung einer zusätzlichen Einschaltbedingung
  
  if($dswoncond && !$defs{$dswoncond}) {
      $err = qq{ERROR - the device "$dswoncond" doesn't exist! Check the key "swoncond" in attribute "consumer${c}"};
      return (0, $info, $err); 
  }  
  
  my $rswoncond     = ConsumerVal ($hash, $c, "rswoncond",     "");             # Reading zur Lieferung einer zusätzlichen Einschaltbedingung
  my $swoncondregex = ConsumerVal ($hash, $c, "swoncondregex", "");             # Regex einer zusätzliche Einschaltbedingung
  my $condstate     = ReadingsVal ($dswoncond, $rswoncond,     "");
  
  if ($condstate =~ m/^$swoncondregex$/x) {                                                     
      return (1, $info, $err);
  }
  
  $info = qq{The device "$dswoncond", reading "$rswoncond" doen't match the Regex "$swoncondregex"};  

return (0, $info, $err);
}

################################################################
#  Funktion liefert "1" wenn die vorrangige Ausschaltbedingung
#  aus dem Schlüssel "swoffcond" im Consumer Attribut wahr ist
#
#  $info - den Info-Status
#  $err  - einen Error-Status
#
################################################################
sub isAddSwitchOffCond {
  my $hash = shift;
  my $c    = shift;

  my $info = q{};
  my $err  = q{};
  
  my $dswoffcond = ConsumerVal ($hash, $c, "dswoffcond", "");                     # Device zur Lieferung einer vorrangigen Ausschaltbedingung
  
  if($dswoffcond && !$defs{$dswoffcond}) {
      $err = qq{ERROR - the device "$dswoffcond" doesn't exist! Check the key "swoffcond" in attribute "consumer${c}"};
      return (0, $info, $err); 
  }  
  
  my $rswoffcond     = ConsumerVal ($hash, $c, "rswoffcond",     "");             # Reading zur Lieferung einer vorrangigen Ausschaltbedingung
  my $swoffcondregex = ConsumerVal ($hash, $c, "swoffcondregex", "");             # Regex einer vorrangigen Ausschaltbedingung
  my $condstate      = ReadingsVal ($dswoffcond, $rswoffcond,    "");
  
  if ($condstate && $condstate =~ m/^$swoffcondregex$/x) {                                                     
      return (1, $info, $err);
  }
  
  $info = qq{The device "$dswoffcond", reading "$rswoffcond" doesn't match the Regex "$swoffcondregex"};  

return (0, $info, $err);
}

################################################################
#  liefert den Status des Timeframe von Consumer $c
################################################################
sub isInTimeframe {
  my $hash = shift;
  my $c    = shift;

return ConsumerVal ($hash, $c, 'isIntimeframe', 0);
}

################################################################
#  liefert den Status "Consumption Recommended" von Consumer $c
################################################################
sub isConsRcmd {
  my $hash = shift;
  my $c    = shift;

return ConsumerVal ($hash, $c, 'isConsumptionRecommended', 0);
}

################################################################
#  ist Consumer $c unterbrechbar (1) oder nicht (0)
################################################################
sub isInterruptible {
  my $hash = shift;
  my $c    = shift;

return ConsumerVal ($hash, $c, 'interruptable', 0);
}

################################################################
#  liefert die Zeit des letzten Schaltvorganges
################################################################
sub lastConsumerSwitchtime {
  my $hash = shift;
  my $c    = shift;
  my $name = $hash->{NAME};  
  
  my $cname = ConsumerVal ($hash, $c, "name", "");                             # Devicename Customer

  if(!$defs{$cname}) {
      Log3($name, 1, qq{$name - the consumer device "$cname" is invalid, the last switching time can't be identified});
      return;
  }
  
  my $rswstate = ConsumerVal           ($hash, $c, "rswstate", "state");       # Reading mit Schaltstatus
  my $swtime   = ReadingsTimestamp     ($cname, $rswstate,          "");       # Zeitstempel im Format 2016-02-16 19:34:24   
  my $swtimets = timestringToTimestamp ($swtime) if($swtime);                  # Unix Timestamp Format erzeugen

return ($swtime, $swtimets);
}

################################################################
#  transformiert den ausführlichen Consumerstatus in eine
#  einfache Form
################################################################
sub simplifyCstate {
  my $ps = shift;  
  
  $ps = $ps =~ /planned/xs        ? 'planned'      :
        $ps =~ /no\splanning/xs   ? 'suspended'    :
        $ps =~ /switching\son/xs  ? 'starting'     :
        $ps =~ /switched\son/xs   ? 'started'      :
        $ps =~ /switching\soff/xs ? 'stopping'     :
        $ps =~ /switched\soff/xs  ? 'finished'     :
        $ps =~ /priority/xs       ? 'priority'     :
        $ps =~ /interrupting/xs   ? 'interrupting' :
        $ps =~ /interrupted/xs    ? 'interrupted'  :
        $ps =~ /continuing/xs     ? 'continuing'   :
        $ps =~ /continued/xs      ? 'continued'    :          
        "unknown";
                
return $ps;
}

###############################################################################
#    Wert des pvhist-Hash zurückliefern
#    Usage:
#    HistoryVal ($hash, $day, $hod, $key, $def)
#
#    $day: Tag des Monats (01,02,...,31)
#    $hod: Stunde des Tages (01,02,...,24,99)
#    $key:    etotal      - totale PV Erzeugung (Wh)
#             pvrl        - realer PV Ertrag
#             pvfc        - PV Vorhersage
#             confc       - Vorhersage Hausverbrauch (Wh)
#             gcons       - realer Netzbezug
#             gfeedin     - reale Netzeinspeisung
#             batintotal  - totale Batterieladung (Wh)
#             batin       - Batterieladung der Stunde (Wh)
#             batouttotal - totale Batterieentladung (Wh)
#             batout      - Batterieentladung der Stunde (Wh)
#             weatherid   - Wetter ID
#             wcc         - Grad der Bewölkung
#             temp        - Außentemperatur
#             wrp         - Niederschlagswahrscheinlichkeit
#             pvcorrf     - PV Autokorrekturfaktor f. Stunde des Tages
#             dayname     - Tagesname (Kürzel)
#             csmt${c}    - Totalconsumption Consumer $c (1..$maxconsumer)
#             csme${c}    - Consumption Consumer $c (1..$maxconsumer) in $hod
#    $def: Defaultwert
#
###############################################################################
sub HistoryVal {
  my $hash = shift;
  my $day  = shift;
  my $hod  = shift;
  my $key  = shift;
  my $def  = shift;
  
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
  if(defined($data{$type}{$name}{pvhist})                    &&
     defined($data{$type}{$name}{pvhist}{$day})              &&
     defined($data{$type}{$name}{pvhist}{$day}{$hod})        &&
     defined($data{$type}{$name}{pvhist}{$day}{$hod}{$key})) {
     return  $data{$type}{$name}{pvhist}{$day}{$hod}{$key};
  }

return $def;
}

################################################################
#    Wert des circular-Hash zurückliefern
#    Achtung: die Werte im circular-Hash haben nicht
#             zwingend eine Beziehung zueinander !!
#
#    Usage:
#    CircularVal ($hash, $hod, $key, $def)
#
#    $hod: Stunde des Tages (01,02,...,24)
#    $key:    pvrl       - realer PV Ertrag
#             pvfc       - PV Vorhersage
#             confc      - Vorhersage Hausverbrauch (Wh)
#             gcons      - realer Netzbezug
#             gfeedin    - reale Netzeinspeisung
#             batin      - Batterieladung (Wh)
#             batout     - Batterieentladung (Wh)
#             weatherid  - DWD Wetter id 
#             weathertxt - DWD Wetter Text
#             wcc        - DWD Wolkendichte
#             wrp        - DWD Regenwahrscheinlichkeit
#             temp       - Außentemperatur
#             pvcorrf    - PV Autokorrekturfaktoren (HASH)
#    $def: Defaultwert
#
################################################################
sub CircularVal {
  my $hash = shift;
  my $hod  = shift;
  my $key  = shift;
  my $def  = shift;
  
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
  if(defined($data{$type}{$name}{circular})              &&
     defined($data{$type}{$name}{circular}{$hod})        &&
     defined($data{$type}{$name}{circular}{$hod}{$key})) {
     return  $data{$type}{$name}{circular}{$hod}{$key};
  }

return $def;
}

################################################################
#    Wert des Autokorrekturfaktors und dessen Qualität
#    für eine bestimmte Bewölkungs-Range aus dem circular-Hash 
#    zurückliefern
#    Usage:
#    ($f,$q) = CircularAutokorrVal ($hash, $hod, $range, $def)
#
#    $f:      Korrekturfaktor f. Stunde des Tages
#    $q:      Qualität des Korrekturfaktors
#
#    $hod:    Stunde des Tages (01,02,...,24)
#    $range:  Range Bewölkung (1...10)
#    $def:    Defaultwert
#
################################################################
sub CircularAutokorrVal {
  my $hash  = shift;
  my $hod   = shift;
  my $range = shift;
  my $def   = shift;
  
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
  my $pvcorrf = $def;
  my $quality = $def;
  
  if(defined($data{$type}{$name}{circular})                         &&
     defined($data{$type}{$name}{circular}{$hod})                   &&
     defined($data{$type}{$name}{circular}{$hod}{pvcorrf})          &&
     defined($data{$type}{$name}{circular}{$hod}{pvcorrf}{$range})) {
     $pvcorrf = $data{$type}{$name}{circular}{$hod}{pvcorrf}{$range};
  }
  
  if(defined($data{$type}{$name}{circular})                         &&
     defined($data{$type}{$name}{circular}{$hod})                   &&
     defined($data{$type}{$name}{circular}{$hod}{quality})          &&
     defined($data{$type}{$name}{circular}{$hod}{quality}{$range})) {
     $quality = $data{$type}{$name}{circular}{$hod}{quality}{$range};
  }

return ($pvcorrf, $quality);
}

################################################################
# Wert des nexthours-Hash zurückliefern
# Usage:
# NexthoursVal ($hash, $hod, $key, $def)
#
# $hod: nächste Stunde (NextHour00, NextHour01,...)
# $key: starttime  - Startzeit der abgefragten nächsten Stunde
#       hourofday  - Stunde des Tages
#       pvforecast - PV Vorhersage
#       weatherid  - DWD Wetter id 
#       cloudcover - DWD Wolkendichte
#       cloudrange - berechnete Bewölkungsrange
#       rainprob   - DWD Regenwahrscheinlichkeit
#       Rad1h      - Globalstrahlung (kJ/m2)
#       confc      - Vorhersage Hausverbrauch (Wh)
#       today      - 1 wenn heute
# $def: Defaultwert
#
################################################################
sub NexthoursVal {
  my $hash = shift;
  my $hod  = shift;
  my $key  = shift;
  my $def  = shift;
  
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
  if(defined($data{$type}{$name}{nexthours})              &&
     defined($data{$type}{$name}{nexthours}{$hod})        &&
     defined($data{$type}{$name}{nexthours}{$hod}{$key})) {
     return  $data{$type}{$name}{nexthours}{$hod}{$key};
  }

return $def;
}

#############################################################################
# Wert des current-Hash zurückliefern
# Usage:
# CurrentVal ($hash, $key, $def)
#
# $key: generation          - aktuelle PV Erzeugung
#       genslidereg         - Schieberegister PV Erzeugung (Array)
#       h4fcslidereg        - Schieberegister 4h PV Forecast (Array)
#       consumerdevs        - alle registrierten Consumerdevices (Array)
#       gridconsumption     - aktueller Netzbezug
#       powerbatin          - Batterie Ladeleistung
#       powerbatout         - Batterie Entladeleistung
#       temp                - aktuelle Außentemperatur
#       tomorrowconsumption - Verbrauch des kommenden Tages
#       invertercapacity    - Bemessungsleistung der Wechselrichters (max. W)
# $def: Defaultwert
#
#############################################################################
sub CurrentVal {
  my $hash = shift;
  my $key  = shift;
  my $def  = shift;  
  
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
  if(defined($data{$type}{$name}{current})       &&
     defined($data{$type}{$name}{current}{$key})) {
     return  $data{$type}{$name}{current}{$key};
  }

return $def;
}

###################################################################################################################
# Wert des consumer-Hash zurückliefern
# Usage:
# ConsumerVal ($hash, $co, $key, $def)
#
# $co:  Consumer Nummer (01,02,03,...)
# $key: name            - Name des Verbrauchers (Device)
#       alias           - Alias des Verbrauchers (Device)
#       type            - Typ des Verbrauchers
#       power           - nominale Leistungsaufnahme des Verbrauchers in W
#       mode            - Planungsmode des Verbrauchers
#       icon            - Icon für den Verbraucher
#       mintime         - min. Einschalt- bzw. Zykluszeit
#       onreg           - Regex für phys. Zustand "ein"
#       offreg          - Regex für phys. Zustand "aus"
#       oncom           - Einschaltkommando 
#       offcom          - Ausschaltkommando
#       onoff           - logischer ein/aus Zustand des am Consumer angeschlossenen Endverbrauchers
#       retotal         - Reading der Leistungsmessung
#       uetotal         - Unit der Leistungsmessung
#       rpcurr          - Readingname des aktuellen Verbrauchs
#       powerthreshold  - Schwellenwert d. aktuellen Leistung(W) ab der ein Verbraucher als aktiv gewertet wird  
#       energythreshold - Schwellenwert (Wh pro Stunde) ab der ein Verbraucher als aktiv gewertet wird  
#       upcurr          - Unit des aktuellen Verbrauchs
#       avgenergy       - initialer / gemessener Durchschnittsverbrauch eines Tages
#       avgruntime      - durchschnittliche Einschalt- bzw. Zykluszeit (Minuten)
#       epieces         - prognostizierte Energiescheiben (Hash)
#       dswoncond       - Device zur Lieferung einer zusätzliche Einschaltbedingung
#       rswoncond       - Reading zur Lieferung einer zusätzliche Einschaltbedingung
#       swoncondregex   - Regex einer zusätzliche Einschaltbedingung
#       dswoffcond      - Device zur Lieferung einer vorrangige Ausschaltbedingung
#       rswoffcond      - Reading zur Lieferung einer vorrangige Ausschaltbedingung
#       swoffcondregex  - Regex einer einer vorrangige Ausschaltbedingung
#       isIntimeframe   - ist Zeit innerhalb der Planzeit ein/aus
#       interruptable   - Consumer "on" ist während geplanter "ein"-Zeit unterbrechbar
#
# $def: Defaultwert
#
####################################################################################################################
sub ConsumerVal {
  my $hash = shift;
  my $co   = shift;
  my $key  = shift;
  my $def  = shift;  
  
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
  if(defined($data{$type}{$name}{consumers})             &&
     defined($data{$type}{$name}{consumers}{$co}{$key})  &&
     defined($data{$type}{$name}{consumers}{$co}{$key})) {
     return  $data{$type}{$name}{consumers}{$co}{$key};
  }

return $def;
}

1;

=pod
=item summary    Visualization of solar predictions for PV systems and Consumer control
=item summary_DE Visualisierung von solaren Vorhersagen für PV Anlagen und Verbrauchersteuerung

=begin html

<a id="SolarForecast"></a>
<h3>SolarForecast</h3>
<br>

=end html
=begin html_DE

<a id="SolarForecast"></a>
<h3>SolarForecast</h3>
<br>

Das Modul SolarForecast erstellt auf Grundlage der Werte aus generischen Quellendevices eine 
Vorhersage für den solaren Ertrag und integriert weitere Informationen als Grundlage für darauf aufbauende Steuerungen. <br>

Die solare Vorhersage basiert auf der durch den Deutschen Wetterdienst (DWD) prognostizierten Globalstrahlung am 
Anlagenstandort. Im zugeordneten DWD_OpenData Device ist die passende Wetterstation mit dem Attribut "forecastStation" 
festzulegen um eine Prognose für diesen Standort zu erhalten. <br>
Abhängig von den DWD-Daten und der physikalischen Anlagengestaltung (Ausrichtung, Winkel, Aufteilung in mehrere Strings, u.a.)
wird auf Grundlage der prognostizierten Globalstrahlung eine wahrscheinliche PV Erzeugung der kommenden Stunden ermittelt. <br>
Darüber hinaus werden Verbrauchswerte bzw. Netzbezugswerte erfasst und für eine Verbrauchsprognose verwendet. <br>
Das Modul errechnet aus den Prognosewerten einen zukünftigen Energieüberschuß der zur Betriebsplanung von Verbrauchern
genutzt wird. Der Nutzer kann Verbraucher (z.B. Schaltsteckdosen) direkt im Modul registrieren und die Planung der 
Ein/Ausschaltzeiten sowie deren Ausführung vom SolarForecast Modul übernehmen lassen.


<ul>
  <a id="SolarForecast-define"></a>
  <b>Define</b>
  <br><br>
  
  <ul>
    Ein SolarForecast Device wird erstellt mit: <br><br>
    
    <ul>
      <b>define &lt;name&gt; SolarForecast </b>
    </ul>
    <br>
    
    Nach der Definition des Devices sind zwingend Vorhersage-Devices des Typs DWD_OpenData zuzuordnen sowie weitere 
    anlagenspezifische Angaben mit den entsprechenden set-Kommandos zu hinterlegen. <br>
    Mit nachfolgenden set-Kommandos werden die Quellendevices und Quellenreadings für maßgebliche Informationen 
    hinterlegt: <br><br>

      <ul>
         <table>
         <colgroup> <col width=35%> <col width=65%> </colgroup>
            <tr><td> <b>currentForecastDev</b>   </td><td>DWD_OpenData Device welches Wetterdaten liefert     </td></tr>
            <tr><td> <b>currentRadiationDev </b> </td><td>DWD_OpenData Device welches Strahlungsdaten liefert </td></tr>
            <tr><td> <b>currentInverterDev</b>   </td><td>Device welches PV Leistungsdaten liefert            </td></tr>
            <tr><td> <b>currentMeterDev</b>      </td><td>Device welches Netz I/O-Daten liefert               </td></tr>
            <tr><td> <b>currentBatteryDev</b>    </td><td>Device welches Batterie Leistungsdaten liefert      </td></tr>            
         </table>
      </ul>
      <br>
      
    Um eine Anpassung an die persönliche Anlage zu ermöglichen, können Korrekturfaktoren manuell 
    (set &lt;name&gt; pvCorrectionFactor_XX) bzw. automatisiert (set &lt;name&gt; pvCorrectionFactor_Auto on) bestimmt 
    werden. <br><br>
    
    <b>Hinweis</b><br>
    Es wird empfohlen die automatische Vorhersagekorrektur unmittelbar einzuschalten, da das SolarForecast Device etliche Tage
    benötigt um eine Optimierung der Korrekturfaktoren zu erreichen.    
 
    <br><br>
  </ul>

  <a id="SolarForecast-set"></a>
  <b>Set</b> 
  <ul>
  
    <ul>
      <a id="SolarForecast-set-consumerImmediatePlanning"></a>
      <li><b>consumerImmediatePlanning &lt;Verbrauchernummer&gt; </b> <br><br>  
      
      Es wird das sofortige Einschalten des Verbrauchers zur aktuellen Zeit eingeplant.  
      Eventuell im consumerXX Attribut gesetzte Schlüssel <b>notbefore</b>, <b>notafter</b> bzw. <b>mode</b> werden nicht 
      beachtet. <br>
      <br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; consumerImmediatePlanning 01 <br>
      </ul>
      </li>
    </ul>
    <br>
  
    <ul>
      <a id="SolarForecast-set-currentBatteryDev"></a>
      <li><b>currentBatteryDev &lt;Meter Device Name&gt; pin=&lt;Readingname&gt;:&lt;Einheit&gt; pout=&lt;Readingname&gt;:&lt;Einheit&gt; [intotal=&lt;Readingname&gt;:&lt;Einheit&gt;] [outtotal=&lt;Readingname&gt;:&lt;Einheit&gt;] [charge=&lt;Readingname&gt;]  </b> <br><br> 
      
      Legt ein beliebiges Device und seine Readings zur Lieferung der Batterie Leistungsdaten fest. 
      Das Modul geht davon aus dass der numerische Wert der Readings immer positiv ist.
      Es kann auch ein Dummy Device mit entsprechenden Readings sein. Die Bedeutung des jeweiligen "Readingname" ist:
      <br>
      
      <ul>   
       <table>  
       <colgroup> <col width=15%> <col width=85%> </colgroup>
          <tr><td> <b>pin</b>       </td><td>Reading welches die aktuelle Batterieladung liefert                         </td></tr>
          <tr><td> <b>pout</b>      </td><td>Reading welches die aktuelle Batterieentladung liefert                      </td></tr>
          <tr><td> <b>intotal</b>   </td><td>Reading welches die totale Batterieladung liefert (fortlaufender Zähler)    </td></tr>
          <tr><td> <b>outtotal</b>  </td><td>Reading welches die totale Batterieentladung liefert (fortlaufender Zähler) </td></tr>
          <tr><td> <b>charge</b>    </td><td>Reading welches den aktuellen Ladezustand (in Prozent) liefert              </td></tr>
          <tr><td> <b>Einheit</b>   </td><td>die jeweilige Einheit (W,Wh,kW,kWh)                                         </td></tr>
        </table>
      </ul> 
      <br>
      
      <b>Sonderfälle:</b> Sollte das Reading für pin und pout identisch, aber vorzeichenbehaftet sein, 
      können die Schlüssel pin und pout wie folgt definiert werden: <br><br>
      <ul>
        pin=-pout  &nbsp;&nbsp;&nbsp;(ein negativer Wert von pout wird als pin verwendet)  <br>
        pout=-pin  &nbsp;&nbsp;&nbsp;(ein negativer Wert von pin wird als pout verwendet)
      </ul>
      <br>
      
      Die Einheit entfällt in dem jeweiligen Sonderfall. <br><br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; currentBatteryDev BatDummy pin=BatVal:W pout=-pin intotal=BatInTot:Wh outtotal=BatOutTot:Wh  <br>
        <br>
        # Device BatDummy liefert die aktuelle Batterieladung im Reading "BatVal" (W), die Batterieentladung im gleichen Reading mit negativen Vorzeichen, <br>
        # die summarische Ladung im Reading "intotal" (Wh), sowie die summarische Entladung im Reading "outtotal" (Wh)
      </ul>      
      </li>
    </ul>
    <br>
  
    <ul>
      <a id="SolarForecast-set-currentForecastDev"></a>
      <li><b>currentForecastDev </b> <br><br> 
      
      Legt das Device (Typ DWD_OpenData) fest, welches die Wetterdaten (Bewölkung, Niederschlag, usw.) liefert. 
      Ist noch kein Device dieses Typs vorhanden, muß es manuell definiert werden 
      (siehe <a href="http://fhem.de/commandref.html#DWD_OpenData">DWD_OpenData Commandref</a>). <br>
      Im ausgewählten DWD_OpenData Device müssen mindestens diese Attribute gesetzt sein: <br><br>

      <ul>
         <table>  
         <colgroup> <col width=25%> <col width=75%> </colgroup>
            <tr><td> <b>forecastDays</b>            </td><td>1                                                   </td></tr>
            <tr><td> <b>forecastProperties</b>      </td><td>TTT,Neff,R101,ww,SunUp,SunRise,SunSet               </td></tr>
            <tr><td> <b>forecastResolution</b>      </td><td>1                                                   </td></tr>         
            <tr><td> <b>forecastStation</b>         </td><td>&lt;Stationscode der ausgewerteten DWD Station&gt;  </td></tr>
         </table>
      </ul>      
      </li>
    </ul>
    <br>
    
    <ul>
      <a id="SolarForecast-set-currentInverterDev"></a>
      <li><b>currentInverterDev &lt;Inverter Device Name&gt; pv=&lt;Readingname&gt;:&lt;Einheit&gt; etotal=&lt;Readingname&gt;:&lt;Einheit&gt; [capacity=&lt;max. WR-Leistung&gt;] </b> <br><br>  
      
      Legt ein beliebiges Device und dessen Readings zur Lieferung der aktuellen PV Erzeugungswerte fest. 
      Es kann auch ein Dummy Device mit entsprechenden Readings sein. 
      Die Werte mehrerer Inverterdevices führt man z.B. in einem Dummy Device zusammen und gibt dieses Device mit den 
      entsprechenden Readings an. <br>
      Die Angabe von <b>capacity</b> ist optional, wird aber zur Optimierung der Vorhersagegenauigkeit dringend empfohlen.
      <br>
      
      <ul>   
       <table>  
       <colgroup> <col width=15%> <col width=85%> </colgroup>
          <tr><td> <b>pv</b>       </td><td>Reading welches die aktuelle PV-Erzeugung liefert                                       </td></tr>
          <tr><td> <b>etotal</b>   </td><td>Reading welches die gesamte erzeugten Energie liefert (ein stetig aufsteigender Zähler) </td></tr>
          <tr><td> <b>Einheit</b>  </td><td>die jeweilige Einheit (W,kW,Wh,kWh)                                                     </td></tr>
          <tr><td> <b>capacity</b> </td><td>Bemessungsleistung des Wechselrichters gemäß Datenblatt (max. möglicher Output in Watt) </td></tr>
        </table>
      </ul> 
      <br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; currentInverterDev STP5000 pv=total_pac:kW etotal=etotal:kWh capacity=5000 <br>
        <br>
        # Device STP5000 liefert PV-Werte. Die aktuell erzeugte Leistung im Reading "total_pac" (kW) und die tägliche Erzeugung im 
          Reading "etotal" (kWh). Die max. Leistung des Wechselrichters beträgt 5000 Watt.
      </ul>
      </li>
    </ul>
    <br>
    
    <ul>
      <a id="SolarForecast-set-currentMeterDev"></a>
      <li><b>currentMeterDev &lt;Meter Device Name&gt; gcon=&lt;Readingname&gt;:&lt;Einheit&gt; contotal=&lt;Readingname&gt;:&lt;Einheit&gt; gfeedin=&lt;Readingname&gt;:&lt;Einheit&gt; feedtotal=&lt;Readingname&gt;:&lt;Einheit&gt;   </b> <br><br> 
      
      Legt ein beliebiges Device und seine Readings zur Energiemessung fest. 
      Das Modul geht davon aus dass der numerische Wert der Readings immer positiv ist.
      Es kann auch ein Dummy Device mit entsprechenden Readings sein. Die Bedeutung des jeweiligen "Readingname" ist:
      <br>
      
      <ul>   
       <table>  
       <colgroup> <col width=15%> <col width=85%> </colgroup>
          <tr><td> <b>gcon</b>       </td><td>Reading welches die aktuell aus dem Netz bezogene Leistung liefert       </td></tr>
          <tr><td> <b>contotal</b>   </td><td>Reading welches die Summe der aus dem Netz bezogenen Energie liefert     </td></tr>
          <tr><td> <b>gfeedin</b>    </td><td>Reading welches die aktuell in das Netz eingespeiste Leistung liefert    </td></tr>
          <tr><td> <b>feedtotal</b>  </td><td>Reading welches die Summe der in das Netz eingespeisten Energie liefert  </td></tr>
          <tr><td> <b>Einheit</b>    </td><td>die jeweilige Einheit (W,kW,Wh,kWh)                                      </td></tr>
        </table>
      </ul> 
      <br>
      
      <b>Sonderfälle:</b> Sollte das Reading für gcon und gfeedin identisch, aber vorzeichenbehaftet sein, 
      können die Schlüssel gfeedin und gcon wie folgt definiert werden: <br><br>
      <ul>
        gfeedin=-gcon  &nbsp;&nbsp;&nbsp;(ein negativer Wert von gcon wird als gfeedin verwendet)  <br>
        gcon=-gfeedin  &nbsp;&nbsp;&nbsp;(ein negativer Wert von gfeedin wird als gcon verwendet)
      </ul>
      <br>
      
      Die Einheit entfällt in dem jeweiligen Sonderfall. <br><br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; currentMeterDev Meter gcon=Wirkleistung:W contotal=BezWirkZaehler:kWh gfeedin=-gcon feedtotal=EinWirkZaehler:kWh  <br>
        <br>
        # Device Meter liefert den aktuellen Netzbezug im Reading "Wirkleistung" (W), 
          die Summe des Netzbezugs im Reading "BezWirkZaehler" (kWh), die aktuelle Einspeisung in "Wirkleistung" wenn "Wirkleistung" negativ ist,
          die Summe der Einspeisung im Reading "EinWirkZaehler" (kWh)
      </ul>      
      </li>
    </ul>
    <br>
    
    <ul>
      <a id="SolarForecast-set-currentRadiationDev"></a>
      <li><b>currentRadiationDev </b> <br><br> 
      
      Legt das Device (Typ DWD_OpenData) fest, welches die solaren Strahlungsdaten liefert. Ist noch kein Device dieses Typs
      vorhanden, muß es manuell definiert werden (siehe <a href="http://fhem.de/commandref.html#DWD_OpenData">DWD_OpenData Commandref</a>). <br>
      Im ausgewählten DWD_OpenData Device müssen mindestens diese Attribute gesetzt sein: <br><br>

      <ul>
         <table> 
         <colgroup> <col width=25%> <col width=75%> </colgroup>
            <tr><td> <b>forecastDays</b>            </td><td>1                                                                                             </td></tr>
            <tr><td> <b>forecastProperties</b>      </td><td>Rad1h                                                                                         </td></tr>
            <tr><td> <b>forecastResolution</b>      </td><td>1                                                                                             </td></tr>         
            <tr><td> <b>forecastStation</b>         </td><td>&lt;Stationscode der ausgewerteten DWD Station&gt;                                            </td></tr>
            <tr><td>                                </td><td><b>Hinweis:</b> Die ausgewählte forecastStation muß Strahlungswerte (Rad1h Readings) liefern. </td></tr>
         </table>
      </ul>      
      </li>
    </ul>
    <br>
    
    <ul>
      <a id="SolarForecast-set-energyH4Trigger"></a>
      <li><b>energyH4Trigger &lt;1on&gt;=&lt;Wert&gt; &lt;1off&gt;=&lt;Wert&gt; [&lt;2on&gt;=&lt;Wert&gt; &lt;2off&gt;=&lt;Wert&gt; ...] </b> <br><br>  
      
      Generiert Trigger bei Über- bzw. Unterschreitung der 4-Stunden PV Vorhersage (NextHours_Sum04_PVforecast). <br>
      Überschreiten die letzten drei Messungen der 4-Stunden PV Vorhersagen eine definierte <b>Xon-Bedingung</b>, wird das Reading 
      <b>energyH4Trigger_X = on</b> erstellt/gesetzt. 
      Unterschreiten die letzten drei Messungen der 4-Stunden PV Vorhersagen eine definierte <b>Xoff-Bedingung</b>, wird das Reading 
      <b>energyH4Trigger_X = off</b> erstellt/gesetzt. <br>
      Es kann eine beliebige Anzahl von Triggerbedingungen angegeben werden. Xon/Xoff-Bedingungen müssen nicht zwingend paarweise
      definiert werden. <br>
      <br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; energyH4Trigger 1on=2000 1off=1700 2on=2500 2off=2000 3off=1500 <br>
      </ul>
      </li>
    </ul>
    <br>
    
    <ul>
      <a id="SolarForecast-set-inverterStrings"></a>
      <li><b>inverterStrings &lt;Stringname1&gt;[,&lt;Stringname2&gt;,&lt;Stringname3&gt;,...] </b> <br><br>  
      
      Bezeichnungen der am Wechselrichter aktiven Strings. Diese Bezeichnungen werden als Schlüssel in den weiteren 
      Settings verwendet. <br><br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; inverterStrings Ostdach,Südgarage,S3 <br>
      </ul>    
      </li>
    </ul>
    <br>
    
    <ul>
      <a id="SolarForecast-set-modulePeakString"></a>
      <li><b>modulePeakString &lt;Stringname1&gt;=&lt;Peak&gt; [&lt;Stringname2&gt;=&lt;Peak&gt; &lt;Stringname3&gt;=&lt;Peak&gt; ...] </b> <br><br> 
      
      Die Peakleistung des Strings "StringnameX" in kWp. Der Stringname ist ein Schlüsselwert des 
      Readings <b>inverterStrings</b>. <br><br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; modulePeakString Ostdach=5.1 Südgarage=2.0 S3=7.2 <br>
      </ul>      
      </li>
    </ul>
    <br>
    
    <ul>
      <a id="SolarForecast-set-moduleDirection"></a>
      <li><b>moduleDirection &lt;Stringname1&gt;=&lt;dir&gt; [&lt;Stringname2&gt;=&lt;dir&gt; &lt;Stringname3&gt;=&lt;dir&gt; ...] </b> <br><br>  
      
      Ausrichtung &lt;dir&gt; der Solarmodule im String "StringnameX". Der Stringname ist ein Schlüsselwert des 
      Readings <b>inverterStrings</b>. <br>
      Die Richtungsangabe &lt;dir&gt; kann eine der folgenden Werte sein: <br><br>

      <ul>
         <table>  
         <colgroup> <col width=10%> <col width=90%> </colgroup>
            <tr><td> <b>N</b>  </td><td>Nordausrichtung            </td></tr>
            <tr><td> <b>NE</b> </td><td>Nord-Ost Ausrichtung       </td></tr>
            <tr><td> <b>E</b>  </td><td>Ostausrichtung             </td></tr>         
            <tr><td> <b>SE</b> </td><td>Süd-Ost Ausrichtung        </td></tr>
            <tr><td> <b>S</b>  </td><td>Südausrichtung             </td></tr>
            <tr><td> <b>SW</b> </td><td>Süd-West Ausrichtung       </td></tr>
            <tr><td> <b>W</b>  </td><td>Westausrichtung            </td></tr>
            <tr><td> <b>NW</b> </td><td>Nord-West Ausrichtung      </td></tr>
         </table>
      </ul> 
      <br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; moduleDirection Ostdach=E Südgarage=S S3=NW <br>
      </ul>       
      </li>
    </ul>
    <br>
    
    <ul>
      <a id="SolarForecast-set-moduleTiltAngle"></a>
      <li><b>moduleTiltAngle &lt;Stringname1&gt;=&lt;Winkel&gt; [&lt;Stringname2&gt;=&lt;Winkel&gt; &lt;Stringname3&gt;=&lt;Winkel&gt; ...] </b> <br><br>  
      
      Neigungswinkel der Solarmodule. Der Stringname ist ein Schlüsselwert des Readings <b>inverterStrings</b>. <br>
      Mögliche Neigungswinkel sind: 0,10,20,25,30,40,45,50,60,70,80,90 (0 = waagerecht, 90 = senkrecht). <br><br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; moduleTiltAngle Ostdach=40 Südgarage=60 S3=30 <br>
      </ul>
      </li>
    </ul>
    <br>
    
    <ul>
      <a id="SolarForecast-set-plantConfiguration"></a>
      <li><b>plantConfiguration </b> <br><br> 
       
       Je nach ausgewählter Kommandooption werden folgende Operationen ausgeführt: <br><br>

      <ul>
         <table>  
         <colgroup> <col width=25%> <col width=75%> </colgroup>
            <tr><td> <b>check</b>     </td><td>Zeigt die aktuelle Stringkonfiguration. Es wird gleichzeitig eine Plausibilitätsprüfung      </td></tr>
            <tr><td>                  </td><td>vorgenommen und das Ergebnis sowie eventuelle Anweisungen zur Fehlerbehebung ausgegeben.     </td></tr>
            <tr><td> <b>save</b>      </td><td>sichert wichtige Parameter der Anlagenkonfiguration                                          </td></tr>
            <tr><td> <b>restore</b>   </td><td>stellt eine gesicherte Anlagenkonfiguration wieder her                                       </td></tr>
         </table>
      </ul>        
      </li>
    </ul>
    <br>
    
    <ul>
      <a id="SolarForecast-set-powerTrigger"></a>
      <li><b>powerTrigger &lt;1on&gt;=&lt;Wert&gt; &lt;1off&gt;=&lt;Wert&gt; [&lt;2on&gt;=&lt;Wert&gt; &lt;2off&gt;=&lt;Wert&gt; ...] </b> <br><br>  
      
      Generiert Trigger bei Über- bzw. Unterschreitung bestimmter PV Erzeugungswerte (Current_PV). <br>
      Überschreiten die letzten drei Messungen der PV Erzeugung eine definierte <b>Xon-Bedingung</b>, wird das Reading 
      <b>powerTrigger_X = on</b> erstellt/gesetzt. 
      Unterschreiten die letzten drei Messungen der PV Erzeugung eine definierte <b>Xoff-Bedingung</b>, wird das Reading 
      <b>powerTrigger_X = off</b> erstellt/gesetzt. <br>
      Es kann eine beliebige Anzahl von Triggerbedingungen angegeben werden. Xon/Xoff-Bedingungen müssen nicht zwingend paarweise
      definiert werden. <br>
      <br>
      
      <ul>
        <b>Beispiel: </b> <br>
        set &lt;name&gt; powerTrigger 1on=1000 1off=500 2on=2000 2off=1000 3on=1600 4off=1100<br>
      </ul>
      </li>
    </ul>
    <br>
    
    <ul>
      <a id="SolarForecast-set-pvCorrectionFactor_Auto"></a>
      <li><b>pvCorrectionFactor_Auto on | off </b> <br><br>  
      
      Schaltet die automatische Vorhersagekorrektur ein/aus. <br>
      Ist die Automatik eingeschaltet, wird für jede Stunde ein Korrekturfaktor der Solarvorhersage berechnet und intern 
      gespeichert.
      Dazu wird die tatsächliche Energieerzeugung mit dem vorhergesagten Wert des aktuellen Tages und Stunde verglichen, 
      die Korrekturwerte historischer Tage unter Berücksichtigung der Bewölkung einbezogen und daraus ein neuer Korrekturfaktor 
      abgeleitet. Es werden nur historische Daten mit gleicher Bewölkungsrange einbezogen. <br>
      Zukünftig erwartete PV Erzeugungen werden mit den gespeicherten Korrekturfaktoren optimiert. <br> 
      Bei aktivierter Autokorrektur haben die Attribute <a href="#cloudFactorDamping">cloudFactorDamping</a> und
      <a href="#rainFactorDamping">rainFactorDamping</a> nur noch eine untergeordnete Bedeutung. <br>
      <b>Die automatische Vorhersagekorrektur ist lernend und benötigt Zeit um die Korrekturwerte zu optimieren.
      Nach der Aktivierung sind nicht sofort optimale Vorhersagen zu erwarten !</b> <br>
      (default: off)      
      </li>
    </ul>
    <br>
    
    <ul>
      <a id="SolarForecast-set-pvCorrectionFactor_" data-pattern="pvCorrectionFactor_.*"></a>
      <li><b>pvCorrectionFactor_XX &lt;Zahl&gt; </b> <br><br> 
      
      Manueller Korrekturfaktor für die Stunde XX des Tages zur Anpassung der Vorhersage an die individuelle Anlage. <br>
      (default: 1.0)      
      </li>
    </ul>
    <br>
    
    <ul>
      <a id="SolarForecast-set-reset"></a>
      <li><b>reset </b> <br><br> 
       
       Löscht die aus der Drop-Down Liste gewählte Datenquelle, zu der Funktion gehörende Readings oder weitere interne 
       Datenstrukturen. <br><br>

      <ul>
         <table>  
         <colgroup> <col width=25%> <col width=75%> </colgroup>                                                                                                              </td></tr>         
            <tr><td> <b>consumerPlanning</b>   </td><td>löscht die Planungsdaten aller registrierten Verbraucher                                                             </td></tr>
            <tr><td>                           </td><td>Um die Planungsdaten nur eines Verbrauchers zu löschen verwendet man:                                                </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset consumerPlanning &lt;Verbrauchernummer&gt; </ul>                                          </td></tr>
            <tr><td>                           </td><td>Das Modul führt eine automatische Neuplanung der Verbraucherschaltung durch.                                         </td></tr>
            <tr><td> <b>consumerMaster</b>     </td><td>löscht die Daten aller registrierten Verbraucher aus dem Speicher                                                    </td></tr>
            <tr><td>                           </td><td>Um die Daten nur eines Verbrauchers zu löschen verwendet man:                                                        </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset consumerMaster &lt;Verbrauchernummer&gt; </ul>                                            </td></tr>
            <tr><td> <b>currentBatteryDev</b>  </td><td>löscht das eingestellte Batteriedevice und korrespondierende Daten                                                   </td></tr>
            <tr><td> <b>currentForecastDev</b> </td><td>löscht das eingestellte Device für Wetterdaten                                                                       </td></tr>
            <tr><td> <b>currentInverterDev</b> </td><td>löscht das eingestellte Inverterdevice und korrespondierende Daten                                                   </td></tr>
            <tr><td> <b>currentMeterDev</b>    </td><td>löscht das eingestellte Meterdevice und korrespondierende Daten                                                      </td></tr>
            <tr><td> <b>energyH4Trigger</b>    </td><td>löscht die 4-Stunden Energie Triggerpunkte                                                                           </td></tr>
            <tr><td> <b>inverterStrings</b>    </td><td>löscht die Stringkonfiguration der Anlage                                                                            </td></tr>
            <tr><td> <b>powerTrigger</b>       </td><td>löscht die Triggerpunkte für PV Erzeugungswerte                                                                      </td></tr>
            <tr><td> <b>pvCorrection</b>       </td><td>löscht die aktuell ermittelten PV Tageskorrekturfaktoren                                                             </td></tr>
            <tr><td>                           </td><td>Um PV Korrekturfaktoren einer bestimmte Stunde aus pvCircular zu löschen:                                            </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset pvCorrection circular &lt;Stunde&gt;  </ul>                                               </td></tr>    
            <tr><td>                           </td><td><ul>(z.B. set &lt;name&gt; reset pvCorrection circular 10)       </ul>                                               </td></tr>            
            <tr><td>                           </td><td>Um alle bisher gespeicherten PV Korrekturfaktoren aus pvCircular zu löschen:                                         </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset pvCorrection circular </ul>                                                               </td></tr>
            <tr><td> <b>pvHistory</b>          </td><td>löscht den Speicher aller historischen Tage (01 ... 31)                                                              </td></tr>
            <tr><td>                           </td><td>Um einen bestimmten historischen Tag zu löschen:                                                                     </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset pvHistory &lt;Tag&gt;   (z.B. set &lt;name&gt; reset pvHistory 08) </ul>                  </td></tr>
            <tr><td>                           </td><td>Um eine bestimmte Stunde eines historischer Tages zu löschen:                                                        </td></tr>
            <tr><td>                           </td><td><ul>set &lt;name&gt; reset pvHistory &lt;Tag&gt; &lt;Stunde&gt;  (z.B. set &lt;name&gt; reset pvHistory 08 10) </ul> </td></tr>
         </table>
      </ul>      
      </li>
    </ul>
    <br>
    
    <ul>
      <a id="SolarForecast-set-writeHistory"></a>
      <li><b>writeHistory </b> <br><br> 
       
       Die vom Device gesammelten historischen PV Daten werden in ein File geschrieben. Dieser Vorgang wird per default 
       regelmäßig im Hintergrund ausgeführt. Im Internal "HISTFILE" wird der Filename und der Zeitpunkt der letzten 
       Speicherung dokumentiert. <br>    
      </li>
    </ul>
    <br>
  
  </ul>
  <br>
  
  <a id="SolarForecast-get"></a>
  <b>Get</b> 
  <ul>       
    <ul>
      <a id="SolarForecast-get-data"></a>
      <li><b>data </b> <br><br> 
      Startet die Datensammlung zur Bestimmung der solaren Vorhersage und anderer Werte.
      </li>      
    </ul>
    <br>
    
    <ul>
      <a id="SolarForecast-get-forecastQualities"></a>
      <li><b>forecastQualities </b> <br><br>
      Zeigt die aktuell verwendeten Korrekturfaktoren mit der jeweiligen Startzeit zur Bestimmung der PV Vorhersage sowie 
      deren Qualitäten an.
      Die Qualität ergibt sich aus der Anzahl der bereits in der Vergangenheit bewerteten Tage mit einer 
      identischen Bewölkungsrange.  
      </li>      
    </ul>
    <br>
    
    <ul>
      <a id="SolarForecast-get-html"></a>
      <li><b>html </b> <br><br>
      Die Solar Grafik wird als HTML-Code abgerufen und wiedergegeben.
      </li>      
    </ul>
    <br>
    
    <ul>
      <a id="SolarForecast-get-nextHours"></a>
      <li><b>nextHours </b> <br><br> 
      Listet die erwarteten Werte der kommenden Stunden auf. <br><br>
      
      <ul>
         <table>  
         <colgroup> <col width=8%> <col width=92%> </colgroup>
            <tr><td> <b>starttime</b> </td><td>Startzeit des Datensatzes                                                          </td></tr>
            <tr><td> <b>hourofday</b> </td><td>laufende Stunde des Tages                                                          </td></tr>
            <tr><td> <b>pvfc</b>      </td><td>erwartete PV Erzeugung                                                             </td></tr>
            <tr><td> <b>today</b>     </td><td>=1 wenn Startdatum am aktuellen Tag                                                </td></tr>
            <tr><td> <b>confc</b>     </td><td>erwarteter Energieverbrauch                                                        </td></tr>
            <tr><td> <b>wid</b>       </td><td>ID des vorhergesagten Wetters                                                      </td></tr> 
            <tr><td> <b>wcc</b>       </td><td>vorhergesagter Grad der Bewölkung                                                  </td></tr>
            <tr><td> <b>crange</b>    </td><td>berechneter Bewölkungsbereich                                                      </td></tr>
            <tr><td> <b>correff</b>   </td><td>effektiv verwendeter Korrekturfaktor/Qualität                                      </td></tr>
            <tr><td>                  </td><td>Faktor/m - manuell                                                                 </td></tr>
            <tr><td>                  </td><td>Faktor/0 - Korrekturfaktor nicht in Store vorhanden (default wird verwendet)       </td></tr>
            <tr><td>                  </td><td>Faktor/1...X - Korrekturfaktor aus Store genutzt (höhere Zahl = bessere Qualität)  </td></tr>
            <tr><td> <b>wrp</b>       </td><td>vorhergesagter Grad der Regenwahrscheinlichkeit                                    </td></tr>
            <tr><td> <b>Rad1h</b>     </td><td>vorhergesagte Globalstrahlung                                                      </td></tr>
            <tr><td> <b>temp</b>      </td><td>vorhergesagte Außentemperatur                                                      </td></tr>        
         </table>
      </ul>
      </li>      
    </ul>
    <br>
    
    <ul>
      <a id="SolarForecast-get-pvHistory"></a>
      <li><b>pvHistory </b> <br><br>
      Listet die historischen Werte der letzten Tage (max. 31) sortiert nach dem Tagesdatum und Stunde. 
      Die Stundenangaben beziehen sich auf die jeweilige Stunde des Tages, z.B. bezieht sich die Stunde 09 auf die Zeit 
      von 08 - 09 Uhr. <br><br>
      
      <ul>
         <table>  
         <colgroup> <col width=20%> <col width=80%> </colgroup>
            <tr><td> <b>etotal</b>         </td><td>totaler Energieertrag (Wh) zu Beginn der Stunde                             </td></tr>
            <tr><td> <b>pvfc</b>           </td><td>der prognostizierte PV Ertrag (Wh)                                          </td></tr>
            <tr><td> <b>pvrl</b>           </td><td>reale PV Erzeugung (Wh)                                                     </td></tr>
            <tr><td> <b>gcon</b>           </td><td>realer Leistungsbezug (Wh) aus dem Stromnetz                                </td></tr>
            <tr><td> <b>confc</b>          </td><td>erwarteter Energieverbrauch (Wh)                                            </td></tr>
            <tr><td> <b>con</b>            </td><td>realer Energieverbrauch (Wh) des Hauses                                     </td></tr>
            <tr><td> <b>gfeedin</b>        </td><td>reale Einspeisung (Wh) in das Stromnetz                                     </td></tr>
            <tr><td> <b>batintotal</b>     </td><td>totale Batterieladung (Wh) zu Beginn der Stunde                             </td></tr>
            <tr><td> <b>batin</b>          </td><td>Batterieladung der Stunde (Wh)                                              </td></tr>
            <tr><td> <b>batouttotal</b>    </td><td>totale Batterieentladung (Wh) zu Beginn der Stunde                          </td></tr>
            <tr><td> <b>batout</b>         </td><td>Batterieentladung der Stunde (Wh)                                           </td></tr>
            <tr><td> <b>wid</b>            </td><td>Identifikationsnummer des Wetters                                           </td></tr>
            <tr><td> <b>wcc</b>            </td><td>effektive Wolkenbedeckung                                                   </td></tr>
            <tr><td> <b>wrp</b>            </td><td>Wahrscheinlichkeit von Niederschlag > 0,1 mm während der jeweiligen Stunde  </td></tr>
            <tr><td> <b>pvcorrf</b>        </td><td>abgeleiteter Autokorrekturfaktor                                            </td></tr>
            <tr><td> <b>csmtXX</b>         </td><td>Summe Energieverbrauch von ConsumerXX                                       </td></tr>
            <tr><td> <b>csmeXX</b>         </td><td>Anteil der jeweiligen Stunde des Tages am Energieverbrauch von ConsumerXX   </td></tr>
            <tr><td> <b>minutescsmXX</b>   </td><td>Summe Aktivminuten in der Stunde von ConsumerXX                             </td></tr>
            <tr><td> <b>hourscsmeXX</b>    </td><td>durchschnittliche Stunden eines Aktivzyklus von ConsumerXX des Tages        </td></tr>
            <tr><td> <b>cyclescsmXX</b>    </td><td>Anzahl aktive Zyklen von ConsumerXX des Tages                                  </td></tr>
         </table>
      </ul>
      </li>      
    </ul>
    <br>
    
    <ul>
      <a id="SolarForecast-get-pvCircular"></a>
      <li><b>pvCircular </b> <br><br>
      Listet die vorhandenen Werte im Ringspeicher auf.  
      Die Stundenangaben beziehen sich auf die Stunde des Tages, z.B. bezieht sich die Stunde 09 auf die Zeit von 08 - 09 Uhr.      
      Erläuterung der Werte: <br><br>
      
      <ul>
         <table>  
         <colgroup> <col width=10%> <col width=90%> </colgroup>
            <tr><td> <b>pvfc</b>     </td><td>PV Vorhersage für die nächsten 24h ab aktueller Stunde des Tages                                                   </td></tr>
            <tr><td> <b>pvrl</b>     </td><td>reale PV Erzeugung der letzten 24h (Achtung: pvforecast und pvreal beziehen sich nicht auf den gleichen Zeitraum!) </td></tr>
            <tr><td> <b>confc</b>    </td><td>erwarteter Energieverbrauch (Wh)                                                                                   </td></tr>
            <tr><td> <b>gcon</b>     </td><td>realer Leistungsbezug aus dem Stromnetz                                                                            </td></tr>
            <tr><td> <b>gfeedin</b>  </td><td>reale Leistungseinspeisung in das Stromnetz                                                                        </td></tr>
            <tr><td> <b>batin</b>    </td><td>Batterieladung                                                                                                     </td></tr>
            <tr><td> <b>batout</b>   </td><td>Batterieentladung                                                                                                  </td></tr>
            <tr><td> <b>wcc</b>      </td><td>Grad der Wolkenüberdeckung                                                                                         </td></tr>
            <tr><td> <b>wrp</b>      </td><td>Grad der Regenwahrscheinlichkeit                                                                                   </td></tr>
            <tr><td> <b>temp</b>     </td><td>Außentemperatur                                                                                                    </td></tr>
            <tr><td> <b>wid</b>      </td><td>ID des vorhergesagten Wetters                                                                                      </td></tr>
            <tr><td> <b>wtxt</b>     </td><td>Beschreibung des vorhergesagten Wetters                                                                            </td></tr>
            <tr><td> <b>corr</b>     </td><td>Autokorrekturfaktoren für die Stunde des Tages und der Bewölkungsrange (0..10)                                     </td></tr>
            <tr><td> <b>quality</b>  </td><td>Qualität der Autokorrekturfaktoren (max. 30), höhere Werte = höhere Qualität                                       </td></tr>
         </table>
      </ul>
      
      </li>      
    </ul>
    <br>
    
    <ul>
      <a id="SolarForecast-get-valConsumerMaster"></a>
      <li><b>valConsumerMaster </b> <br><br>
      Listet die aktuell ermittelten Stammdaten der im Device registrierten Verbraucher auf.
      </li>      
    </ul>
    <br>
    
    <ul>
      <a id="SolarForecast-get-valCurrent"></a>
      <li><b>valCurrent </b> <br><br>
      Listet aktuelle Betriebsdaten, Kennzahlen und Status auf.
      </li>      
    </ul>
    <br>
    
  </ul>
  <br>

  <a id="SolarForecast-attr"></a>
  <b>Attribute</b>
  <br><br>
  <ul>
     <ul>
        <a id="SolarForecast-attr-alias"></a>
        <li><b>alias </b> <br>
          In Verbindung mit "showLink" ein beliebiger Anzeigename.
        </li>
        <br>  
       
       <a id="SolarForecast-attr-autoRefresh"></a>
       <li><b>autoRefresh</b> <br>
         Wenn gesetzt, werden aktive Browserseiten des FHEMWEB-Devices welches das SolarForecast-Device aufgerufen hat, nach der 
         eingestellten Zeit (Sekunden) neu geladen. Sollen statt dessen Browserseiten eines bestimmten FHEMWEB-Devices neu 
         geladen werden, kann dieses Device mit dem Attribut "autoRefreshFW" festgelegt werden.
       </li>
       <br>
    
       <a id="SolarForecast-attr-autoRefreshFW"></a>
       <li><b>autoRefreshFW</b><br>
         Ist "autoRefresh" aktiviert, kann mit diesem Attribut das FHEMWEB-Device bestimmt werden dessen aktive Browserseiten
         regelmäßig neu geladen werden sollen.
       </li>
       <br>
    
       <a id="SolarForecast-attr-beam1Color"></a>
       <li><b>beam1Color </b><br>
         Farbauswahl der primären Balken.  
       </li>
       <br>
       
       <a id="SolarForecast-attr-beam1Content"></a>
       <li><b>beam1Content </b><br>
         Legt den darzustellenden Inhalt der primären Balken fest.
       
         <ul>   
         <table>  
         <colgroup> <col width=15%> <col width=85%> </colgroup>
            <tr><td> <b>pvForecast</b>          </td><td>prognostizierte PV-Erzeugung (default) </td></tr>
            <tr><td> <b>pvReal</b>              </td><td>reale PV-Erzeugung                     </td></tr>
            <tr><td> <b>gridconsumption</b>     </td><td>Energie Bezug aus dem Netz             </td></tr>
            <tr><td> <b>consumptionForecast</b> </td><td>prognostizierter Energieverbrauch      </td></tr>
         </table>
         </ul>       
       </li>
       <br> 
       
       <a id="SolarForecast-attr-beam2Color"></a>
       <li><b>beam2Color </b><br>
         Farbauswahl der sekundären Balken. Die zweite Farbe ist nur sinnvoll für den Anzeigedevice-Typ "pvco" und "diff".
       </li>
       <br>  
       
       <a id="SolarForecast-attr-beam2Content"></a>
       <li><b>beam2Content </b><br>
         Legt den darzustellenden Inhalt der sekundären Balken fest. 

         <ul>   
         <table>  
         <colgroup> <col width=15%> <col width=85%> </colgroup>
            <tr><td> <b>pvForecast</b>          </td><td>prognostizierte PV-Erzeugung (default) </td></tr>
            <tr><td> <b>pvReal</b>              </td><td>reale PV-Erzeugung                     </td></tr>
            <tr><td> <b>gridconsumption</b>     </td><td>Energie Bezug aus dem Netz             </td></tr>
            <tr><td> <b>consumptionForecast</b> </td><td>prognostizierter Energieverbrauch      </td></tr>
         </table>
         </ul>        
       </li>
       <br>
       
       <a id="SolarForecast-attr-beamHeight"></a>
       <li><b>beamHeight &lt;value&gt; </b><br>
         Höhe der Balken in px und damit Bestimmung der gesammten Höhe.
         In Verbindung mit "hourCount" lassen sich damit auch recht kleine Grafikausgaben erzeugen. <br>
         (default: 200)
       </li>
       <br>
       
       <a id="SolarForecast-attr-beamWidth"></a>
       <li><b>beamWidth &lt;value&gt; </b><br>
         Breite der Balken in px. <br>
         (default: 6 (auto))
       </li>
       <br>  
       
       <a id="SolarForecast-attr-cloudFactorDamping"></a>
       <li><b>cloudFactorDamping </b><br>
         Prozentuale Berücksichtigung (Dämpfung) des Bewölkungprognosefaktors bei der solaren Vorhersage. <br>
         Größere Werte vermindern, kleinere Werte erhöhen tendenziell den prognostizierten PV Ertrag.<br>
         (default: 35)         
       </li>  
       <br> 
       
       <a id="SolarForecast-attr-consumerAdviceIcon"></a>
       <li><b>consumerAdviceIcon </b><br>
         Definiert die Art der Information über die geplanten Schaltzeiten eines Verbrauchers in der Verbraucherlegende.
         <br><br>       
         <ul>   
         <table>  
         <colgroup> <col width=10%> <col width=90%> </colgroup>
            <tr><td> <b>&lt;Icon&gt@&lt;Farbe&gt</b>  </td><td>Aktivierungsempfehlung  wird durch Icon und Farbe (optional) dargestellt (default: light_light_dim_100@gold)  </td></tr>
            <tr><td>                                  </td><td>(die Planungsdaten werden als Mouse-Over Text angezeigt                                                       </td></tr>
            <tr><td> <b>times</b>                     </td><td>es werden der Planungsstatus und die geplanten Schaltzeiten als Text angezeigt                                </td></tr>
            <tr><td> <b>none</b>                      </td><td>keine Anzeige der Planungsdaten                                                                               </td></tr>
         </table>
         </ul>
       </li>
       <br> 

       <a id="SolarForecast-attr-consumerLegend"></a>
       <li><b>consumerLegend </b><br>
         Definiert die Lage bzw. Darstellungsweise der Verbraucherlegende sofern Verbraucher SolarForecast Device 
         registriert sind. <br>
         (default: icon_top)
       </li>
       <br>       
       
       <a id="SolarForecast-attr-consumer" data-pattern="consumer.*"></a>
       <li><b>consumerXX &lt;Device Name&gt; type=&lt;type&gt; power=&lt;power&gt; [mode=&lt;mode&gt;] [icon=&lt;Icon&gt;] [mintime=&lt;minutes&gt;] <br>
                         [on=&lt;Kommando&gt;] [off=&lt;Kommando&gt;] [swstate=&lt;Readingname&gt;:&lt;on-Regex&gt;:&lt;off-Regex&gt] [notbefore=&lt;Stunde&gt;] [notafter=&lt;Stunde&gt;] <br>
                         [auto=&lt;Readingname&gt;] [pcurr=&lt;Readingname&gt;:&lt;Einheit&gt;[:&lt;Schwellenwert&gt]] [etotal=&lt;Readingname&gt;:&lt;Einheit&gt;[:&lt;Schwellenwert&gt]] <br>
                         [swoncond=&lt;Device&gt;:&lt;Reading&gt;:&lt;Regex&gt] [swoffcond=&lt;Device&gt;:&lt;Reading&gt;:&lt;Regex&gt] [interruptable=0|1] </b><br><br>
        
        Registriert einen Verbraucher &lt;Device Name&gt; beim SolarForecast Device. Dabei ist &lt;Device Name&gt;
        ein in FHEM bereits angelegtes Verbraucher Device, z.B. eine Schaltsteckdose.
        Die meisten Schlüssel sind optional, sind aber für bestimmte Funktionalitäten Voraussetzung und werden mit 
        default-Werten besetzt. <br>
        Ist der Schüssel "auto" definiert, kann der Automatikmodus in der integrierten Verbrauchergrafik mit den 
        entsprechenden Drucktasten umgeschaltet werden. Das angegebene Reading wird ggf. im Consumer Device angelegt falls
        es nicht vorhanden ist. <br><br>
        
        Mit dem optionalen Schlüssel <b>swoncond</b> kann eine <b>zusätzliche externe Bedingung</b> definiert werden um den Einschaltvorgang des 
        Consumers freizugeben. Ist die Bedingung (Regex) nicht erfüllt, erfolgt kein Einschalten des Verbrauchers auch wenn die 
        sonstigen Voraussetzungen wie Zeitplanung, on-Schlüssel, auto-Mode und aktuelle PV-Leistung gegeben sind. Es erfolgt somit eine 
        <b>UND-Verknüpfung</b> des Schlüssels swoncond mit den weiteren Einschaltbedingungen. <br><br>

        Der optionale Schlüssel <b>swoffcond</b> definiert eine <b>vorrangige Ausschaltbedingung</b> (Regex). Sobald diese 
        Bedingung erfüllt ist, wird der Consumer ausgeschaltet auch wenn die geplante Endezeit (consumerXX_planned_stop) 
        noch nicht erreicht ist (<b>ODER-Verknüpfung</b>). Weitere Bedingungen wie off-Schlüssel und auto-Mode müssen
        zum automatischen Ausschalten erfüllt sein. <br><br>

        Mit dem optionalen Schlüssel <b>interruptable</b> kann während der geplanten Einschaltzeit eine automatische 
        Unterbrechung sowie Wiedereinschaltung des Verbrauchers vorgenommen werden sofern der Schlüssel mode=must nicht
        gesetzt ist.
        Unterschreitet der PV Überschuß die benötigte Energie, wird der Verbraucher ausgeschaltet (interrupted) und 
        eingeschaltet wenn wieder ausreichend PV Überschuß vorhanden ist (continued). 
        Die verbleibende Laufzeit wird durch einen Interrupt nicht beeinflusst ! 
        <br><br>
         <ul>   
         <table>  
         <colgroup> <col width=12%> <col width=88%> </colgroup>
            <tr><td> <b>type</b>           </td><td>Typ des Verbrauchers. Folgende Typen sind erlaubt:                                                                               </td></tr>
            <tr><td>                       </td><td><b>dishwasher</b>     - Verbaucher ist eine Spülamschine                                                                         </td></tr>
            <tr><td>                       </td><td><b>dryer</b>          - Verbaucher ist ein Wäschetrockner                                                                        </td></tr>
            <tr><td>                       </td><td><b>washingmachine</b> - Verbaucher ist eine Waschmaschine                                                                        </td></tr>
            <tr><td>                       </td><td><b>heater</b>         - Verbaucher ist ein Heizstab                                                                              </td></tr>
            <tr><td>                       </td><td><b>charger</b>        - Verbaucher ist eine Ladeeinrichtung (Akku, Auto, etc.)                                                   </td></tr>
            <tr><td>                       </td><td><b>other</b>          - Verbraucher ist keiner der vorgenannten Typen                                                            </td></tr>          
            <tr><td> <b>power</b>          </td><td>typische Leistungsaufnahme des Verbrauchers (siehe Datenblatt) in W                                                              </td></tr>            
            <tr><td> <b>mode</b>           </td><td>Planungsmodus des Verbrauchers (optional). Erlaubt sind:                                                                         </td></tr>
            <tr><td>                       </td><td><b>can</b>  - der Verbaucher kann angeschaltet werden wenn genügend Energie bereitsteht (default)                                </td></tr>
            <tr><td>                       </td><td><b>must</b> - der Verbaucher muß einmal am Tag angeschaltet werden auch wenn nicht genügend Energie vorhanden ist                </td></tr>
            <tr><td> <b>icon</b>           </td><td>Icon zur Darstellung des Verbrauchers in der Übersichtsgrafik (optional)                                                         </td></tr>
            <tr><td> <b>mintime</b>        </td><td>Mindestlaufzeit bzw. typische Laufzeit für einen Zyklus des Verbrauchers nach dem Einschalten in Minuten, mind. 60 (optional)    </td></tr>
            <tr><td> <b>on</b>             </td><td>Set-Kommando zum Einschalten des Verbrauchers (optional)                                                                         </td></tr>
            <tr><td> <b>off</b>            </td><td>Set-Kommando zum Ausschalten des Verbrauchers (optional)                                                                         </td></tr>
            <tr><td> <b>swstate</b>        </td><td>Reading welches den Schaltzustand des Consumers anzeigt (default: 'state').                                                      </td></tr>
            <tr><td>                       </td><td><b>on-Regex</b> - regulärer Ausdruck für den Zustand 'ein' (default: 'on')                                                       </td></tr>
            <tr><td>                       </td><td><b>off-Regex</b> - regulärer Ausdruck für den Zustand 'aus' (default: 'off')                                                     </td></tr>
            <tr><td> <b>notbefore</b>      </td><td>Verbraucher nicht vor angegebener Stunde (01..23) einschalten (optional)                                                         </td></tr>
            <tr><td> <b>notafter</b>       </td><td>Verbraucher nicht nach angegebener Stunde (01..23) einschalten (optional)                                                        </td></tr>
            <tr><td> <b>auto</b>           </td><td>Reading im Verbraucherdevice welches das Schalten des Verbrauchers freigibt bzw. blockiert (optional)                            </td></tr>
            <tr><td>                       </td><td>Readingwert = 1 - Schalten freigegeben (default),  0: Schalten blockiert                                                         </td></tr>
            <tr><td> <b>pcurr</b>          </td><td>Reading:Einheit (W/kW) welches den aktuellen Energieverbrauch liefert (optional)                                                 </td></tr>
            <tr><td>                       </td><td>:&lt;Schwellenwert&gt (W) - aktuelle Leistung ab welcher der Verbraucher als aktiv gewertet wird.                                </td></tr>
            <tr><td> <b>etotal</b>         </td><td>Reading:Einheit (Wh/kWh) des Consumer Device, welches die Summe der verbrauchten Energie liefert (optional)                      </td></tr>
            <tr><td>                       </td><td>:&lt;Schwellenwert&gt (Wh) - Energieverbrauch pro Stunde ab dem der Verbraucher als aktiv gewertet wird.                         </td></tr>
            <tr><td> <b>swoncond</b>       </td><td>zusätzliche Bedingung die erfüllt sein muß um den Verbraucher einzuschalten (optional).                                          </td></tr>
            <tr><td>                       </td><td><b>Device</b> - Device zur Lieferung der zusätzlichen Einschaltbedingung                                                         </td></tr>
            <tr><td>                       </td><td><b>Reading</b> - Reading zur Lieferung der zusätzlichen Einschaltbedingung                                                       </td></tr>
            <tr><td>                       </td><td><b>Regex</b> - regulärer Ausdruck der für die Einschaltbedingung erfüllt sein muß                                                </td></tr>
            <tr><td> <b>swoffcond</b>      </td><td>vorrangige Bedingung um den Verbraucher auszuschalten (optional).                                                                </td></tr>
            <tr><td>                       </td><td><b>Device</b> - Device zur Lieferung der vorrangigen Ausschaltbedingung                                                          </td></tr>
            <tr><td>                       </td><td><b>Reading</b> - Reading zur Lieferung der vorrangigen Ausschaltbedingung                                                        </td></tr>
            <tr><td>                       </td><td><b>Regex</b> - regulärer Ausdruck der für die Ausschaltbedingung erfüllt sein muß                                                </td></tr>
            <tr><td> <b>interruptable</b>  </td><td>Verbraucher darf (optional) unterbrechbar (1) oder nicht unterbrechbar (0) sein (default: 0)                                     </td></tr>
         </table>
         </ul>
       <br>
      
       <ul>
         <b>Beispiele: </b> <br>
         attr &lt;name&gt; consumer01 wallplug icon=scene_dishwasher@orange type=dishwasher mode=can power=2500 on=on off=off notafter=20 etotal=total:kWh:5 <br>
         attr &lt;name&gt; consumer02 WPxw type=heater mode=can power=3000 mintime=180 on="on-for-timer 3600" notafter=12 auto=automatic                     <br>
         attr &lt;name&gt; consumer03 Shelly.shellyplug2 type=other power=300 mode=must icon=it_ups_on_battery mintime=120 on=on off=off swstate=state:on:off auto=automatic pcurr=relay_0_power:W etotal:relay_0_energy_Wh:Wh swoncond=EcoFlow:data_data_socSum:^-?([1-7][0-9]|[0-9])$ swoffcond:EcoFlow:data_data_socSum:100 <br>
       </ul> 
       </li>  
       <br>
       
       <a id="SolarForecast-attr-createConsumptionRecReadings"></a>
       <li><b>createConsumptionRecReadings </b><br>
         Für die ausgewählten Consumer (Nummer) werden Readings der Form <b>consumerXX_ConsumptionRecommended</b> erstellt. <br>
         Diese Readings signalisieren ob das Einschalten dieses Consumers abhängig von seinen Verbrauchsdaten und der aktuellen
         PV-Erzeugung bzw. des aktuellen Energieüberschusses empfohlen ist. Der Wert des erstellten Readings korreliert 
         mit den berechneten Planungsdaten das Consumers, kann aber von dem Planungszeitraum abweichen. <br>
       <br>       
         
       </li>
       <br>  
       
       <a id="SolarForecast-attr-createTomorrowPVFcReadings"></a>
       <li><b>createTomorrowPVFcReadings &lt;01,02,..,24&gt; </b><br>
         Wenn gesetzt, werden Readings der Form <b>Tomorrow_Hour&lt;hour&gt;_PVforecast</b> erstellt. <br>
         Diese Readings enthalten die voraussichtliche PV Erzeugung des kommenden Tages. Dabei ist &lt;hour&gt; die 
         Stunde des Tages. <br>
       <br>
      
       <ul>
         <b>Beispiel: </b> <br>
         attr &lt;name&gt; createTomorrowPVFcReadings 09,11 <br>
         # erstellt Readings für die Stunde 09 (08:00-09:00) und 11 (10:00-11:00) des kommenden Tages
       </ul>         
         
       </li>
       <br> 
       
       <a id="SolarForecast-attr-Css"></a>
       <li><b>Css </b><br>
         Definiert den Style für die Energieflußgrafik. Das Attribut wird automatisch vorbelegt. 
         Zum Ändern des Css-Attributes bitte den Default übernehmen und anpassen: <br><br>
         
         <ul>   
           .flowg.text           { stroke: none; fill: gray; font-size: 32px; } <br>    
           .flowg.sun_active     { stroke: orange; fill: orange; }              <br>                                          
           .flowg.sun_inactive   { stroke: gray; fill: gray; }                  <br>                                         
           .flowg.bat25          { stroke: red; fill: red; }                    <br>                                        
           .flowg.bat50          { stroke: yellow; fill: yellow; }              <br>                                       
           .flowg.bat75          { stroke: green; fill: green; }                <br>                                    
           .flowg.grid_color1    { fill: green; }                               <br>           
           .flowg.grid_color2    { fill: red; }                                 <br>                                    
           .flowg.grid_color3    { fill: gray; }                                <br>                                    
           .flowg.inactive_in    { stroke: gray;   stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.2; }    <br>
           .flowg.inactive_out   { stroke: gray;   stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.2; }    <br>
           .flowg.active_in      { stroke: red;    stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.8; animation: dash 0.5s linear; animation-iteration-count: infinite; }   <br>
           .flowg.active_out     { stroke: yellow; stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.8; animation: dash 0.5s linear; animation-iteration-count: infinite; }   <br>
           .flowg.active_bat_in  { stroke: yellow; stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.8; animation: dash 0.5s linear; animation-iteration-count: infinite; }  <br>
           .flowg.active_bat_out { stroke: green; stroke-dashoffset: 20; stroke-dasharray: 10; opacity: 0.8; animation: dash 0.5s linear; animation-iteration-count: infinite; }  <br>                                                                                                                                                                                                                             
         </ul>   
         
       </li>
       <br> 
  
       <a id="SolarForecast-attr-debug"></a>
       <li><b>debug</b><br>
         Aktiviert/deaktiviert Debug-Meldungen im Modul.
       </li>
       <br>
       
       <a id="SolarForecast-attr-disable"></a>
       <li><b>disable</b><br>
         Aktiviert/deaktiviert das Device.
       </li>
       <br>
       
       <a id="SolarForecast-attr-flowGraphicAnimate"></a>
       <li><b>flowGraphicAnimate </b><br>
         Animiert die Energieflußgrafik sofern angezeigt. 
         Siehe auch Attribut <a href="#SolarForecast-attr-graphicSelect">graphicSelect</a>. <br>
         (default: 0)
       </li>
       <br>
       
       <a id="SolarForecast-attr-flowGraphicConsumerDistance"></a>
       <li><b>flowGraphicConsumerDistance </b><br>
         Steuert den Abstand zwischen den Consumer-Icons in der Energieflußgrafik sofern angezeigt. 
         Siehe auch Attribut <a href="#SolarForecast-attr-flowGraphicShowConsumer">flowGraphicShowConsumer</a>. <br>
         (default: 80)
       </li>
       <br>
       
       <a id="SolarForecast-attr-flowGraphicShowConsumer"></a>
       <li><b>flowGraphicShowConsumer </b><br>
         Unterdrückt die Anzeige der Verbraucher in der Energieflußgrafik wenn auf "0" gesetzt. <br> 
         (default: 1)
       </li>
       <br>
       
       <a id="SolarForecast-attr-flowGraphicShowConsumerDummy"></a>
       <li><b>flowGraphicShowConsumerDummy </b><br>
         Zeigt bzw. unterdrückt den Dummy-Verbraucher in der Energieflußgrafik. <br> 
         Dem Dummy-Verbraucher stellt den Energieverbrauch dar der anderen Verbrauchern nicht zugeordnet werden konnte. <br>
         (default: 1)
       </li>
       <br>    
       
       <a id="SolarForecast-attr-flowGraphicShowConsumerPower"></a>
       <li><b>flowGraphicShowConsumerPower </b><br>
         Zeigt bzw. unterdrückt den Energieverbrauch der Verbraucher in der Energieflußgrafik. <br> 
         (default: 1)
       </li>
       <br> 
       
       <a id="SolarForecast-attr-flowGraphicShowConsumerRemainTime"></a>
       <li><b>flowGraphicShowConsumerRemainTime </b><br>
         Zeigt bzw. unterdrückt die Restlaufzeit (in Minuten) der Verbraucher in der Energieflußgrafik. <br> 
         (default: 1)
       </li>
       <br> 
       
       <a id="SolarForecast-attr-flowGraphicSize"></a>
       <li><b>flowGraphicSize &lt;Pixel&gt; </b><br>
         Größe der Energieflußgrafik sofern angezeigt. 
         Siehe auch Attribut <a href="#SolarForecast-attr-graphicSelect">graphicSelect</a>. <br>
         (default: 300)
       </li>
       <br>
       
       <a id="SolarForecast-attr-follow70percentRule"></a>
       <li><b>follow70percentRule</b><br>
         Wenn gesetzt, wird die prognostizierte Leistung entsprechend der 70% Regel begrenzt. <br><br>
         
         <ul>   
         <table>  
         <colgroup> <col width=15%> <col width=85%> </colgroup>
            <tr><td> <b>0</b>       </td><td>keine Begrenzung der prognostizierten PV-Erzeugung (default)                                 </td></tr>
            <tr><td> <b>1</b>       </td><td>die prognostizierte PV-Erzeugung wird auf 70% der installierten Stringleistung(en) begrenzt  </td></tr>
            <tr><td> <b>dynamic</b> </td><td>die prognostizierte PV-Erzeugung wird begrenzt wenn 70% der installierten                    </td></tr>
            <tr><td>                </td><td>Stringleistung(en) zzgl. des prognostizierten Verbrauchs überschritten wird                  </td></tr>
         </table>
         </ul> 
       </li>
       <br>
     
       <a id="SolarForecast-attr-forcePageRefresh"></a>
       <li><b>forcePageRefresh</b><br>
         Das Attribut wird durch das SMAPortal-Device ausgewertet. <br>
         Wenn gesetzt, wird ein Reload aller Browserseiten mit aktiven FHEMWEB-Verbindungen nach dem Update des 
         Eltern-SMAPortal-Devices erzwungen.    
       </li>
       <br>
       
       <a id="SolarForecast-attr-graphicSelect"></a>
       <li><b>graphicSelect </b><br>
         Wählt die anzuzeigende interne Grafik des Moduls aus. <br>
         Zur Anpassung der Energieflußgrafik steht das Attribut <a href="#SolarForecast-attr-Css">Css</a> zur 
         Verfügung. <br><br>
         
         <ul>   
         <table>  
         <colgroup> <col width=15%> <col width=85%> </colgroup>
            <tr><td> <b>flow</b>       </td><td>zeigt die Energieflußgrafik an                          </td></tr>
            <tr><td> <b>forecast</b>   </td><td>zeigt die Vorhersagegrafik an                           </td></tr>
            <tr><td> <b>both</b>       </td><td>zeigt Energiefluß- und Vorhersagegrafik an (default)    </td></tr>
            <tr><td> <b>none</b>       </td><td>es wird keine Grafik angezeigt                          </td></tr>
         </table>
         </ul> 
       </li>
       <br>
       
       <a id="SolarForecast-attr-historyHour"></a>
       <li><b>historyHour </b><br>
         Anzahl der vorangegangenen Stunden die in der Balkengrafik dargestellt werden. <br>
         (default: 0)
       </li>
       <br>
       
       <a id="SolarForecast-attr-hourCount"></a>
       <li><b>hourCount &lt;4...24&gt; </b><br>
         Anzahl der Balken/Stunden. <br>
         (default: 24)
       </li>
       <br>
       
       <a id="SolarForecast-attr-headerDetail"></a>
       <li><b>headerDetail </b><br>
         Detailiierungsgrad der Kopfzeilen. <br>
         (default: all)
         
         <ul>   
         <table>  
         <colgroup> <col width=10%> <col width=90%> </colgroup>
            <tr><td> <b>all</b>        </td><td>Anzeige Erzeugung (PV), Verbrauch (CO), Link zur Device Detailanzeige + Aktualisierungszeit (default) </td></tr>
            <tr><td> <b>co</b>         </td><td>nur Verbrauch (CO)                                                                                    </td></tr>
            <tr><td> <b>pv</b>         </td><td>nur Erzeugung (PV)                                                                                    </td></tr>
            <tr><td> <b>pvco</b>       </td><td>Erzeugung (PV) und Verbrauch (CO)                                                                     </td></tr>         
            <tr><td> <b>statusLink</b> </td><td>Link zur Device Detailanzeige + Aktualisierungszeit                                                   </td></tr>
         </table>
         </ul>       
       </li>
       <br>                                      
       
       <a id="SolarForecast-attr-hourStyle"></a>
       <li><b>hourStyle </b><br>
         Format der Zeitangabe. <br><br>
       
       <ul>   
         <table>  
           <colgroup> <col width=30%> <col width=70%> </colgroup>
           <tr><td> <b>nicht gesetzt</b>  </td><td>nur Stundenangabe ohne Minuten (default)                </td></tr>
           <tr><td> <b>:00</b>            </td><td>Stunden sowie Minuten zweistellig, z.B. 10:00           </td></tr>
           <tr><td> <b>:0</b>             </td><td>Stunden sowie Minuten einstellig, z.B. 8:0              </td></tr>
         </table>
       </ul>       
       </li>
       <br>
       
       <a id="SolarForecast-attr-htmlStart"></a>
       <li><b>htmlStart &lt;HTML-String&gt; </b><br>
         Angabe eines beliebigen HTML-Strings der vor dem Grafik-Code ausgeführt wird. 
       </li>
       <br>

       <a id="SolarForecast-attr-htmlEnd"></a>
       <li><b>htmlEnd &lt;HTML-String&gt; </b><br>
         Angabe eines beliebigen HTML-Strings der nach dem Grafik-Code ausgeführt wird. 
       </li>
       <br> 
       
       <a id="SolarForecast-attr-interval"></a>
       <li><b>interval &lt;Sekunden&gt; </b><br>
         Zeitintervall der Datensammlung. <br>
         Ist interval explizit auf "0" gesetzt, erfolgt keine automatische Datensammlung und muss mit "get &lt;name&gt; data" 
         manuell erfolgen. <br>
         (default: 70)
       </li><br>
       
       <a id="SolarForecast-attr-layoutType"></a>
       <li><b>layoutType &lt;single | double | diff&gt; </b><br>
       Layout der integrierten Grafik. <br>
       Der darzustellende Inhalt der Balken wird durch die Attribute <b>beam1Content</b> bzw. <b>beam2Content</b> 
       bestimmt. <br>
       (default: single)  
       <br><br>
       
       <ul>   
       <table>  
       <colgroup> <col width=5%> <col width=95%> </colgroup>
          <tr><td> <b>single</b>  </td><td>- zeigt nur den primären Balken an                                                                               </td></tr>
          <tr><td> <b>double</b>  </td><td>- zeigt den primären Balken und den sekundären Balken an                                                         </td></tr>
          <tr><td> <b>diff</b>    </td><td>- Differenzanzeige. Es gilt:  &lt;Differenz&gt; = &lt;Wert primärer Balken&gt; - &lt;Wert sekundärer Balken&gt;  </td></tr>
       </table>
       </ul>
       </li>
       <br> 
 
       <a id="SolarForecast-attr-maxValBeam"></a>
       <li><b>maxValBeam &lt;0...val&gt; </b><br>
         Festlegung des maximalen Betrags des primären Balkens (Stundenwert) zur Berechnung der maximalen Balkenhöhe. 
         Dadurch erfolgt eine Anpassung der zulässigen Gesamthöhe der Grafik. <br>
         Wenn nicht gesetzt oder 0, erfolgt eine dynamische Anpassung. <br>
         (default: 0)
       </li>
       <br>
       
       <a id="SolarForecast-attr-maxVariancePerDay"></a>
       <li><b>maxVariancePerDay &lt;Zahl&gt; </b><br>
         Maximale Änderungsgröße des PV Vorhersagefaktors (Reading pvCorrectionFactor_XX) pro Tag. <br>
         (default: 0.5)
       </li>
       <br>
       
       <a id="SolarForecast-attr-numHistDays"></a>
       <li><b>numHistDays </b><br>
         Anzahl der historischen Tage aus Cache 'pvHistory' die zur Autokorrektur der PV Vorhersage verwendet werden. <br>
         (default: alle verfügbaren Daten in pvHistory und pvCircular)
       </li>
       <br>
       
       <a id="SolarForecast-attr-preferredChargeBattery"></a>
       <li><b>preferredChargeBattery </b><br>
         Es werden Verbraucher mit dem Mode <b>can</b> erst dann eingeschaltet, wenn die angegebene Batterieladung (%)
         erreicht ist. <br>
         Verbraucher mit dem Mode <b>must</b> beachten die Vorrangladung der Batterie nicht. <br>
         (default: 0)
       </li>
       <br>
       
       <a id="SolarForecast-attr-rainFactorDamping"></a>
       <li><b>rainFactorDamping </b><br>
         Prozentuale Berücksichtigung (Dämpfung) des Regenprognosefaktors bei der solaren Vorhersage. <br>
         Größere Werte vermindern, kleinere Werte erhöhen tendenziell den prognostizierten PV Ertrag.<br>
         (default: 10)         
       </li>  
       <br> 
       
       <a id="SolarForecast-attr-sameWeekdaysForConsfc"></a>
       <li><b>sameWeekdaysForConsfc </b><br>
         Wenn gesetzt, werden zur Berechnung der Verbrauchsprognose nur gleiche Wochentage (Mo..So) einbezogen. <br>
         Anderenfalls werden alle Wochentage gleichberechtigt zur Kalkulation verwendet. <br>
         (default: 0)
       </li>
       <br>
       
   
       <a id="SolarForecast-attr-showDiff"></a>
       <li><b>showDiff &lt;no | top | bottom&gt; </b><br>
         Zusätzliche Darstellung der Differenz "beam1Content - beam2Content" im Kopf- oder Fußbereich der Anzeige. <br>
         (default: no)
       </li>
       <br>
       
       <a id="SolarForecast-attr-showHeader"></a>
       <li><b>showHeader </b><br>
         Anzeige der Kopfzeile mit Prognosedaten, Rest des aktuellen Tages und des nächsten Tages <br>
         (default: 1)
       </li>
       <br>
       
       <a id="SolarForecast-attr-showLink"></a>
       <li><b>showLink </b><br>
         Anzeige des Detail-Links über dem Grafik-Device <br>
         (default: 1)
       </li>
       <br>
       
       <a id="SolarForecast-attr-showNight"></a>
       <li><b>showNight </b><br>
         Die Nachtstunden (ohne Ertragsprognose) werden mit angezeigt. <br>
         (default: 0)
       </li>
       <br>

       <a id="SolarForecast-attr-showWeather"></a>
       <li><b>showWeather </b><br>
         Wettericons anzeigen. <br>
         (default: 1)
       </li>
       <br> 
       
       <a id="SolarForecast-attr-spaceSize"></a>
       <li><b>spaceSize &lt;value&gt; </b><br>
         Legt fest wieviel Platz in px über oder unter den Balken (bei Anzeigetyp Differential (diff)) zur Anzeige der 
         Werte freigehalten wird. Bei Styles mit große Fonts kann der default-Wert zu klein sein bzw. rutscht ein 
         Balken u.U. über die Grundlinie. In diesen Fällen bitte den Wert erhöhen. <br>
         (default: 24)
       </li>
       <br>
       
       <a id="SolarForecast-attr-Wh/kWh"></a>
       <li><b>Wh/kWh &lt;Wh | kWh&gt; </b><br>
         Definiert die Anzeigeeinheit in Wh oder in kWh auf eine Nachkommastelle gerundet. <br>
         (default: W)
       </li>
       <br>   

       <a id="SolarForecast-attr-weatherColor"></a>
       <li><b>weatherColor </b><br>
         Farbe der Wetter-Icons.
       </li>
       <br> 

       <a id="SolarForecast-attr-weatherColorNight"></a>
       <li><b>weatherColorNight </b><br>
         Farbe der Wetter-Icons für die Nachtstunden.
       </li>
       <br>        

     </ul>
  </ul>
  
</ul>

=end html_DE

=for :application/json;q=META.json 76_SolarForecast.pm
{
  "abstract": "Creation of solar predictions for PV systems",
  "x_lang": {
    "de": {
      "abstract": "Erstellung solarer Vorhersagen von PV Anlagen"
    }
  },
  "keywords": [
    "inverter",
    "photovoltaik",
    "electricity",
    "forecast",
    "graphics",
    "Autarky",
    "Consumer",
    "PV"
  ],
  "version": "v1.1.1",
  "release_status": "testing",
  "author": [
    "Heiko Maaz <heiko.maaz@t-online.de>"
  ],
  "x_fhem_maintainer": [
    "DS_Starter"
  ],
  "x_fhem_maintainer_github": [
    "nasseeder1"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.014,
        "POSIX": 0,
        "GPUtils": 0,
        "Encode": 0,
        "Color": 0,
        "utf8": 0,
        "JSON": 4.020,
        "Data::Dumper": 0,
        "FHEM::SynoModules::SMUtils": 1.0220,
        "Time::HiRes": 0        
      },
      "recommends": {
        "FHEM::Meta": 0
      },
      "suggests": {
      }
    }
  },
  "resources": {
    "repository": {
      "x_dev": {
        "type": "svn",
        "url": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter",
        "web": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter/76_SolarForecast.pm",
        "x_branch": "dev",
        "x_filepath": "fhem/contrib/",
        "x_raw": "https://svn.fhem.de/fhem/trunk/fhem/contrib/DS_Starter/76_SolarForecast.pm"
      }      
    }
  }
}
=end :application/json;q=META.json

=cut
