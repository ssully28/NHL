#!/usr/bin/perl -w
use strict;
use POSIX qw(strftime);
use Getopt::Long qw(:config no_ignore_case);
use Text::CSV::Simple;
use Text::TabularDisplay;
use File::Copy;
use Data::Dumper;
$Data::Dumper::Indent = 1;

##---------------------------------------------##
# Multipliers:
my $MULTI_FPPG      = 1500;    # Fanduel Points Average       
my $MULTI_GAA       = 1900;    # Goals Against Average        
my $MULTI_SHA       = 12;      # Shots Against Per Game       
my $MULTI_PK        = 9;       # Team PK Percentage (negative)
my $MULTI_SPLIT_GAA = 1400;    # Splits Save Percentage       
my $MULTI_SPLIT_PK  = 8;       # Splits PK (negative)         

##---------------------------------------------##
# NHL Game Digest
#
# http://www.nhl.com/gamecenter/en/boxscore?id=2015020516

my $player_file;
my $player_data = [];
my $TeamStats = {};
my $TeamSplits = {};

my $downloads_folder    = '/Users/stevensullivan/Downloads';
my $archive_folder      = '/Users/stevensullivan/Dev/Perl/Projects/FanDuel/ArchivedPlayerFiles';
my $team_archive_folder = '/Users/stevensullivan/Dev/Perl/Projects/FanDuel/NHL_DATA_FILES/ArchivedDataFiles';

# Fetch Team Data from (Save in Text File):
# NO GOOD NOW: http://www.nhl.com/stats/team?reportType=season&report=teamsummary&season=20172016&gameType=2&aggregate=0
# http://sports.yahoo.com/nhl/stats/byteam?cat=teamstats&sort=444
# NOTE - make sure you fix Montreal - need to remove the funny e
my $team_data_file      = '/Users/stevensullivan/Dev/Perl/Projects/FanDuel/NHL_DATA_FILES/NHL_TEAM_STATS.txt';

# Fetch Splits Data from:
# HOME: http://sports.yahoo.com/nhl/stats/byteam?cat=splits&conference=NHL&year=season_2017&cut_type=33
# AWAY: http://sports.yahoo.com/nhl/stats/byteam?cat=splits&conference=NHL&year=season_2017&cut_type=34
my $splits_home_file    = '/Users/stevensullivan/Dev/Perl/Projects/FanDuel/NHL_DATA_FILES/NHL_SPLITS_HOME.txt';
my $splits_away_file    = '/Users/stevensullivan/Dev/Perl/Projects/FanDuel/NHL_DATA_FILES/NHL_SPLITS_AWAY.txt';

# NHL Abb to Full Name Map
my $AbbrToName = {
  'PIT' => 'Pittsburgh Penguins',   
  'NYR' => 'New York Rangers',      
  'MON' => 'Montreal Canadiens',    
  'FLA' => 'Florida Panthers',      
  'STL' => 'St. Louis Blues',       
  'LA'  => 'Los Angeles Kings',     
  'NSH' => 'Nashville Predators',   
  'CHI' => 'Chicago Blackhawks',    
  'VAN' => 'Vancouver Canucks',     
  'WAS' => 'Washington Capitals',   
  'NYI' => 'New York Islanders',    
  'SJ'  => 'San Jose Sharks',       
  'TB'  => 'Tampa Bay Lightning',   
  'NJ'  => 'New Jersey Devils',     
  'WPG' => 'Winnipeg Jets',         
  'ANA' => 'Anaheim Ducks',         
  'ANH' => 'Anaheim Ducks',         
  'CAR' => 'Carolina Hurricanes',   
  'DAL' => 'Dallas Stars',          
  'DET' => 'Detroit Red Wings',     
  'PHI' => 'Philadelphia Flyers',   
  'COL' => 'Colorado Avalanche',    
  'PHO' => 'Arizona Coyotes',       
  'ARI' => 'Arizona Coyotes',       
  'MIN' => 'Minnesota Wild',        
  'BUF' => 'Buffalo Sabres',        
  'OTT' => 'Ottawa Senators',       
  'BOS' => 'Boston Bruins',         
  'EDM' => 'Edmonton Oilers',       
  'TOR' => 'Toronto Maple Leafs',   
  'CLS' => 'Columbus Blue Jackets', 
  'CGY' => 'Calgary Flames',        
};


##------------------------------------------------------------##
## Handle Options

my $move_files              = 1;
my $no_move                 = 0;
my $include_injured_players = 0;
my $print_bargains          = 1;
my $exclude_splits          = 1;
my $print_highvalue         = 0;
my $gaa_weight              = 0;
my $pk_weight			    = 0;


# Let's allow for some command line voodoo:
&GetOptions(
            "n|nomove"         => \$no_move,
            "i|iip"            => \$include_injured_players,
            "b|bargains"       => \$print_bargains,
#            "e|exclude"        => \$exclude_splits,
#            "h|highvalue"      => \$print_highvalue,
            "G|GAA=s"          => \$gaa_weight,              # Over-ride GAA weight
            "P|PK=s"           => \$pk_weight,               # Over-ride PK weight
            );




##------------------------------------------------------------##
## Get Team Data

&GetTeamStats();
#&GetTeamSplits();   // Need to find a new source...comment out for now


##------------------------------------------------------------##
## Over-rides:

if ($gaa_weight) {
  $MULTI_GAA = ($gaa_weight/100) * $MULTI_GAA;
}

if ($pk_weight) {
  $MULTI_PK = ($pk_weight/100) * $MULTI_PK;
}


##------------------------------------------------------------##
## Let's do dis!

my $files_found = 0;
opendir (DIR, $downloads_folder) or die $!;

while (my $file_name = readdir(DIR)) {

    next unless ($file_name =~ /^(FanDuel)-(NHL)-(\d{4}-\d{2}-\d{2}).*\.csv$/);
    $files_found++;
    my $source = $1;
    my $sport = $2;
    my $date = $3;
    
    print "\n$source - $sport player data for:  $date\n\n";
    
    #If we get here, we found a file - yay!
    # Move file:
    unless ($no_move) {
        my $src_file_path = $downloads_folder . '/' . $file_name;
        my $dest_file_path = $archive_folder . '/' . $file_name;
        $player_file = $dest_file_path;
        
        print "  FROM:  $src_file_path\n";
        print "    TO:  $dest_file_path\n";
        move("$src_file_path","$dest_file_path");
    }
    else {
        $player_file = $downloads_folder . '/' . $file_name;
        print "  Processing $player_file (NOT MOVING)\n";
        
    }
}


my $parser = Text::CSV::Simple->new;
$parser->field_map(qw/Id Position First_Name Last_Name FPPG Played Salary Game Team Opponent Injury_Indicator Injury_Details/);
my @data = $parser->read_file($player_file);

# Load Players Into Positional Hashes (i.e., %goalies, %leftwings, etc...)
my $LeftWings = [];
my $RightWings = [];
my $Centers = [];
my $DMen = [];
my $Goalies = [];
my $Wingers = [];
my $Bargains = [];
my $HighValue = [];

foreach my $player (@data) {
  
  # Skip this record if it's the header:
  next if ($player->{FPPG} eq "FPPG");
  

  # Don't show injured players unless I ask for them!
  unless ($include_injured_players) {
    next if ($player->{Injury_Indicator} =~ /O|IR/);
  }
  
  
  # Figure out Opponent's Split (home or away)
#  my $opponent_split;
#  my ($home_team, $away_team) = split(/\@/, $player->{Game});
#                                         
#  if ($player->{Team} eq $home_team) {
#    # Player is at home, so opponent is away!
#    $opponent_split = "away";
#  }                   
#  elsif ($player->{Team} eq $away_team)  {
#    # Player is away, so opponent is home!
#    $opponent_split = "home";
#  }
#  else {
#    print "---------------------------\n";
#    print Dumper($player);
#    die "\nERROR:  Cannot figure home or away\n";
#  }                        
  
  
  
  my $player_rank = 0;
  
  my $opponent = $player->{Opponent} || "NA";
  
  my $opponent_name = $AbbrToName->{$opponent} || 'NA';
  
  if ($opponent_name eq 'NA') {
    die "Could not find team name via abbreviation:  $opponent\n";
  }
  
  
  
  if ($player->{Position} eq 'G') {
    next;
  }
  else {
    
    ##-----------------------------##
    ## STATS CALCULATIONS:
    
    # Goals Against Average Score
    my $oppn_gga = $TeamStats->{$opponent_name}->{gga} * $MULTI_GAA;
    
    # Fanduel Points Per Game Score
    my $fppg = ($player->{FPPG} || 0) * $MULTI_FPPG;
  
    # Shots Per Game Score
    my $oppn_spg = $TeamStats->{$opponent_name}->{sa} * $MULTI_SHA;
    
    # Penalty Kill Score
    my $oppn_pk = $TeamStats->{$opponent_name}->{pk} * $MULTI_PK;
    
    # SPLITS Goals Against Average Score:
    #my $oppn_split_gga = $TeamSplits->{$opponent_name}->{$opponent_split}->{gaa} * $MULTI_SPLIT_GAA;
    
    
    # SPLITS Penalty Kill Score:
    #my $oppn_split_pk = $TeamSplits->{$opponent_name}->{$opponent_split}->{pk} * $MULTI_SPLIT_PK;
  
    
    ##-----------------------------##
    # Calculate My Player Rank:
    $player_rank = $fppg + $oppn_gga + $oppn_spg - $oppn_pk;
    
    #unless($exclude_splits) {
    #    $player_rank = $player_rank + $oppn_split_gga - $oppn_split_pk;
    #}

  }

  $player->{myrank} = $player_rank;
  
  
  if ($player->{Salary} < 5000) {
    push(@$Bargains, $player);
  }
  
  # High Value Targets:
  if ($player->{Position} eq 'D') {
    if ($player->{Salary} < 5000) {
      push(@$HighValue, $player);    
    }
  }
  elsif ($player->{Position} ne 'G') {
  	# Hmmm, not sure I want to bother with
    # goalie selection now....so few
  }
  else {
  	if ($player->{Salary} < 7600) {
  	  push(@$HighValue, $player);
  	}
  }

  if ($player->{Position} eq 'LW') {
    push(@$LeftWings, $player);
  }
  elsif ($player->{Position} eq 'RW') {
    push(@$RightWings, $player);
  }
  elsif ($player->{Position} eq 'C') {
    push(@$Centers, $player);
  }
  elsif ($player->{Position} eq 'D') {
    push(@$DMen, $player);
  }
  elsif ($player->{Position} eq 'G') {
    push(@$Goalies, $player);
  }
  elsif ($player->{Position} eq 'W') {
    push(@$Wingers, $player);
  }
}

$LeftWings = SortArray($LeftWings);
$RightWings = SortArray($RightWings);
$Centers = SortArray($Centers);
$DMen = SortArray($DMen);
$Goalies = SortArray($Goalies);
$Bargains = SortArray($Bargains);
$HighValue = SortArray($HighValue);
$Wingers = SortArray($Wingers);


print "CENTERS:\n";
PrintTopTargetsTable($Centers);
# FD no longer separates wings into R/L,
# now just "Wingers"....YAY!

#print "RIGHT WINGS:\n";
#PrintTopTargetsTable($RightWings);
#print "LEFT WINGS:\n";
#PrintTopTargetsTable($LeftWings);
print "Wingers:\n";
PrintTopTargetsTable($Wingers);
print "DEFENSEMEN:\n";
PrintTopTargetsTable($DMen);

# Not bothering with Goalies for now
# Need to incorporate Opponents Team Offensive Stats for that
# print "GOALIES:\n";
# PrintTopTargets($Goalies);

if ($print_bargains) {
  print "BARGAINS:\n";
  PrintTopTargetsTable($Bargains);  
}

if ($print_highvalue) {
  print "HIGH VALUE TARGETS:\n";
  PrintTopTargetsTable($HighValue);
}

sub PrintTopTargets {
    my $arrayRef = shift;
    
    my $count = 0;
    my $number = 15;

    foreach my $player (@$arrayRef) {
      print "$player->{Last_Name}, $player->{First_Name}     $player->{Salary}     $player->{myrank}     $player->{Opponent}     $player->{FPPG}\n";
      $count++;
      last if ($count >= $number);
    }
    
    print "\n" x 3;
}

sub PrintTopTargetsTable {
    my $arrayRef = shift;
    
    my $count = 0;
    my $number = 15;
    
    my @columns = qw(Last_Name First_Name Salary MyRank Opponent FPPG);
    my @row;
    
    my $table = Text::TabularDisplay->new(@columns);

    foreach my $player(@$arrayRef) {
      my $my_rank = sprintf("%.0f", $player->{myrank});
      $player->{FPPG} = sprintf("%.3f", $player->{FPPG});
      @row = split(/\|/, qq($player->{Last_Name}|$player->{First_Name}|$player->{Salary}|$my_rank|$player->{Opponent}|$player->{FPPG}));
      
      $table->add(@row);
      $count++;
    
      last if ($count >= $number);
    }    
        
    print $table->render;
    
    print "\n" x 3;
}


sub SortArray {
    my $arrayRef = shift;
    
    @$arrayRef = sort { $b->{myrank} <=> $a->{myrank} or 
                        $b->{Salary} <=> $a->{Salary} 
                      } @$arrayRef;
    
    return $arrayRef;
}


# TO DO:
#  Load player data into database
#  Want to be able to see trends (last X number of days who have risen the most

# Fetch Team Data from:
# http://www.nhl.com/stats/team?reportType=season&report=teamsummary&season=20152016&gameType=2&aggregate=0
# Save in Text File
# 
sub GetTeamStats {
    print "Getting Team Data....\n";

    my $parser = Text::CSV::Simple->new({ sep => "\t"} );
    
    $parser->field_map(qw/Team GP G A GFA SOG Pct PIM GA GAA SV SV% SO EGA W L T OTL/);
    #$parser->field_map(qw/rank team season games_played wins losses ties ot_losses points total_wins point_per goals_for goals_against goals_for_pergame goals_against_pergame pp_per pk_per shots_pergame shots_against_pergame faceoff_per/);
    my @team_data = $parser->read_file($team_data_file);
    
    #print Dumper(@team_data);
    
    
    foreach my $line (@team_data) {
        my $team = &strip_trailing_spaces($line->{Team});
        #$team =~ s/\s+$//;
        
        
        #print ">$team<\n";    
        # Load Team Stats:
        $TeamStats->{$team}->{gga} = $line->{GAA};
        $TeamStats->{$team}->{pk} = $line->{pk_per};
        $TeamStats->{$team}->{sa} = $line->{shots_against_pergame};
        
    }
    
}

sub GetTeamSplits {
  {
    print "Getting Team Splits (HOME)....\n";   
    my $parser = Text::CSV::Simple->new({ sep => "\t"} );
    
    $parser->field_map(qw/team blank gp blank1 goals_for blank2 assists blank3 sog blank4 pct blank5 goals_against blank6 saves blank7 save_per blank8 pp_per blank9 pk_per/);
    my @team_data = $parser->read_file($splits_home_file);
    
    
    foreach my $line (@team_data) {
        my $team = &strip_trailing_spaces($line->{team});
        my $games_played = &strip_trailing_spaces($line->{gp}) || 0;
        my $gf = &strip_trailing_spaces($line->{goals_for}) || 0;
        my $ga = &strip_trailing_spaces($line->{goals_against}) || 0;
        
        my $gfa = 0;
        my $gaa = 0;
        
#       print "TEAM ->$team<-\n";
#       print "GP ->$games_played<-\n";
#       print "GF ->$line->{goals_for}<-\n";
#       print "A  ->$line->{assists}<-\n";
#       print "GA ->$line->{goals_against}\n";
#       print "PK ->$line->{pk_per}\n";
#       print "SOG ->$line->{sog}\n";
        $gfa = $gf/$games_played if ($games_played);
        $gaa = $ga/$games_played if ($games_played);
        
        $TeamSplits->{$team}->{home}->{gf} = &strip_trailing_spaces($line->{goals_for});
        $TeamSplits->{$team}->{home}->{ga} = &strip_trailing_spaces($line->{goals_against});
        $TeamSplits->{$team}->{home}->{pk} = &strip_trailing_spaces($line->{pk_per});
        $TeamSplits->{$team}->{home}->{pp} = &strip_trailing_spaces($line->{pp_per});
        $TeamSplits->{$team}->{home}->{sp} = &strip_trailing_spaces($line->{save_per});
        
        $TeamSplits->{$team}->{home}->{gfa} = $gfa;
        $TeamSplits->{$team}->{home}->{gaa} = $gaa;
    }
  }
  
  
  {
    print "Getting Team Splits (AWAY)....\n";
    my $parser = Text::CSV::Simple->new({ sep => "\t"} );
    
    $parser->field_map(qw/team blank gp blank1 goals_for blank2 assists blank3 sog blank4 pct blank5 goals_against blank6 saves blank7 save_per blank8 pp_per blank9 pk_per/);
    my @team_data = $parser->read_file($splits_away_file);
    
    
    foreach my $line (@team_data) {
        my $team = &strip_trailing_spaces($line->{team});
        my $games_played = &strip_trailing_spaces($line->{gp}) || 0;
        my $gf = &strip_trailing_spaces($line->{goals_for}) || 0;
        my $ga = &strip_trailing_spaces($line->{goals_against}) || 0;
        
        my $gfa = 0;
        my $gaa = 0;
        
        $gfa = $gf/$games_played if ($games_played);
        $gaa = $ga/$games_played if ($games_played);
        $TeamSplits->{$team}->{away}->{gf} = &strip_trailing_spaces($line->{goals_for});
        $TeamSplits->{$team}->{away}->{ga} = &strip_trailing_spaces($line->{goals_against});
        $TeamSplits->{$team}->{away}->{pk} = &strip_trailing_spaces($line->{pk_per});  
        $TeamSplits->{$team}->{away}->{pp} = &strip_trailing_spaces($line->{pp_per});  
        $TeamSplits->{$team}->{away}->{sp} = &strip_trailing_spaces($line->{save_per});

        $TeamSplits->{$team}->{away}->{gfa} = $gfa;
        $TeamSplits->{$team}->{away}->{gaa} = $gaa;
    }
  }
  
}

sub strip_trailing_spaces {
  my $value = shift;
  
  $value =~ s/\s+$//;
  
  return $value;
}


__END__

  'goals_for' => '51',
  'goals_against' => '62',
  'ties' => '0',
  'goals_against_pergame' => '2.70',
  'points' => '19',
  'shots_pergame' => '30.1',
  'pk_per' => '79.7',
  'wins' => '7',
  'losses' => '11',
  'ot_losses' => '5',
  'point_per' => '41.3',
  'total_wins' => '5',
  'shots_against_pergame' => '31.0',
  'pp_per' => '19.7',
  'games_played' => '23',
  'goals_for_pergame' => '2.22',
  'team' => 'Toronto Maple Leafs',
  'rank' => '30',
  'faceoff_per' => '50.5',
  'season' => '2015-2016'

# Fields Available per Player:
#   $player->{Injury_Indicator};
#   $player->{Team};
#   $player->{Position};
#   $player->{Id};
#   $player->{Salary};
#   $player->{Opponent};
#   $player->{Game};
#   $player->{Last_Name};
#   $player->{FPPG};
#   $player->{Injury_Details};
#   $player->{First_Name};
#   $player->{Played};


# Rules:
#  Must be at or under the salary cap
#  Must not have more than 4 players from any one team
#  Must have 2 LW, 2 RW, 2 C, 2 D, 1 G