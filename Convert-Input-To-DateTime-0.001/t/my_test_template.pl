use strict;
use warnings;
use Modern::Perl q/2012/;
use DateTime;

#-------------------------------------------------------------------------------
# Globals
#-------------------------------------------------------------------------------
use vars qw/$ControlDateTime $ControlDateDay $MyModule/;

#-------------------------------------------------------------------------------
#  Begin
#-------------------------------------------------------------------------------

#------ chdir to the dir the test directory. Now we always know where we are
#       relative to other files.
BEGIN {
    use File::Spec::Functions;
    use FindBin qw/$Bin/;

    #------ test script dir
    chdir $Bin if -d $Bin;

    #------ Include our application dir and our own lib dir
    use lib "$Bin/../lib";
    use lib "$Bin/lib";

    $MyModule = 'Convert::Input::To::DateTime';

   #------ Note,  because this is included in the script in t/ FindBin finds the
   #------ location of the test script,  not this inc.pl script.

    #------ Set up Smart Comments in the test Environment only
    $ENV{SMART_COMMENTS} = '###:####';

    #----- Set Testing ENV
    $ENV{APP_TEST} = 1;
}

#-------------------------------------------------------------------------------
# Populate Globals
#-------------------------------------------------------------------------------
$ControlDateTime = DateTime->now();
$ControlDateDay  = DateTime->today();
$MyModule        = 'Convert::Input::To::DateTime';

#-------------------------------------------------------------------------------
#  Include Modules
#-------------------------------------------------------------------------------
use File::Spec::Functions;

#use YAML qw/Dump/;
use Data::Dump qw/dump/;

#-------------------------------------------------------------------------------
#  The End
#-------------------------------------------------------------------------------
1;
