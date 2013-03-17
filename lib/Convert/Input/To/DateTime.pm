use Modern::Perl q/2012/;
use autodie;

package Convert::Input::To::DateTime;
use Moose::Role;
use namespace::autoclean;

our $VERSION = q/0.001/;    # from D Golden blog
$VERSION = eval $VERSION;

use Scalar::Util qw/tainted blessed reftype/;
use String::Util qw/trim crunch hascontent/;
use Log::Any qw/$log/;
use DateTime;
use Data::Dump qw/dump/;
use Regexp::Common qw(time);
use Try::Tiny;

use Mover::Date::Types qw/
  MoverDateTime
  MoverDateStrYearFirst
  MoverDateStrMonthFirst
  MoverDateStrDayFirst
  MoverTimeStrHourFirst
  MoverDateTimeStrIso
  MoverDateHref
  MoverDateTimeHref
  /;

use MooseX::Types::Common::String qw/NonEmptyStr/;

#------ Constants
use Readonly;
Readonly my $FAIL            => undef;
Readonly my $EMPTY           => q/<empty>/;
Readonly my $DATE_TIME_CLASS => q/DateTime/;

#------ Mover Date Specific constants
Readonly my $UTC_TZ => 'UTC';

#-------------------------------------------------------------------------------
#  Generic Convert input data to a DateTime Object.
#-------------------------------------------------------------------------------
#----- Taint check and trim the date string before converting to a DateTime
around 'convert_to_datetime' => sub {
    my $orig = shift;
    my $self = shift;
    my $input_date =
      $self->_str_has_untainted_content_or_confess( trim(shift) );
    return $self->$orig($input_date);
};

=head convert_to_datetime 
 Takes a date of unknown type and endeavours to convert it to a DateTime
 Object.
 Tests for date as a 1.DateTime Object, 2.ISO-1860 string , 3.yyyymmdd,
 4.mmddyyyy, 5.ddmmyyyy, 6.HashRef, 7.DateTime::Natural::Format recognized string.
 Returns a DateTime Object.

=cut

sub convert_to_datetime {
    my $self       = shift;
    my $input_date = shift;
    my ( $MyDateTime, $date_str );

    #------ Base Date Time obtained by validating the input date type
    #      The 'around' method modifier has established that $iput_date
    #      is defined.
  SWITCH: {

        #--- DateTime Object
        ( blessed($input_date)
              and ( blessed($input_date) eq $DATE_TIME_CLASS ) )
          && do {
            $log->debug('A DateTime object was passed to base_date param!');
            $MyDateTime = $input_date;
            last SWITCH;
          };

        #--- Bad Object
        (         ( blessed $input_date )
              and ( blessed $input_date ne $DATE_TIME_CLASS ) )
          && do {
            $log->error('An unrecognied object was passed to base_date param!');
            $MyDateTime = $FAIL;
            last SWITCH;
          };

        #------ HashRef input
        ( ref($input_date) eq 'HASH' ) && do {
            ### A HashRef was sent to convert_to_datetime : $input_date
            #--- HashRef with Date and Time
            ( $date_str = to_MoverDateTimeHref($input_date) )
              && do {
                $log->debug(
                    'Its a Date Time HashRef(year) : ' . $date_str->{year} );
                $MyDateTime = $self->_format_hashref_to_datetime($date_str);

                #--- Done! if we have a DateTime object
                last SWITCH
                  if ( $MyDateTime && $MyDateTime->isa($DATE_TIME_CLASS) );
              };

            #--- HashRef with Date Only
            ( $date_str = to_MoverDateHref($input_date) )
              && do {
                $log->debug('Its a DateTimeHref!');
                $MyDateTime = $self->_format_hashref_to_datetime($date_str);
                last SWITCH;
              };
        };    #--- End HashRef Check

        #------ Check Srtings for Dates
        $log->debug( 'Pre checking string for date format: '
              . ( $input_date // $EMPTY ) );
        (
            is_NonEmptyStr($input_date)
              && (
                $input_date = $self->_str_has_untainted_content_or_confess(
                    crunch($input_date)
                )
              )
          )
          && do {

            #--- YYYY-MM-DDTHH:MM:SS ISO-8060
            ( $date_str = to_MoverDateTimeStrIso($input_date) )
              && do {
                $log->debug( 'Its an ISO Date String: ' . $date_str );
                $MyDateTime = $self->_format_iso_string_to_datetime_tz(
                    { date_str => $date_str } );

                last SWITCH
                  if ( $MyDateTime && $MyDateTime->isa($DATE_TIME_CLASS) );
              };

            #--- yyyymmdd
            ( $date_str = to_MoverDateStrYearFirst($input_date) )
              && do {
                $log->debug( 'Its an yyyymmdd Date String: ' . $date_str );
                $MyDateTime = $self->_format_yyyymmdd_to_datetime_tz(
                    { date_str => $date_str } );

                last SWITCH
                  if ( $MyDateTime && $MyDateTime->isa($DATE_TIME_CLASS) );
              };

            #--- mmddyyyy
            ( $date_str = to_MoverDateStrMonthFirst($input_date) )
              && do {
                $log->debug( 'Its an mmddyyyy Date String: ' . $date_str );
                $MyDateTime = $self->_format_mmddyyyy_to_datetime_tz(
                    { date_str => $date_str } );

                last SWITCH
                  if ( $MyDateTime && $MyDateTime->isa($DATE_TIME_CLASS) );
              };

            #--- ddmmyyyy (European style)
            ( $date_str = to_MoverDateStrDayFirst($input_date) )
              && do {
                $log->debug( 'Its an ddmmyyyy Date String: ' . $date_str );
                $MyDateTime = $self->_format_ddmmyyyy_to_datetime_tz(
                    { date_str => $date_str } );
                last SWITCH
                  if ( $MyDateTime && $MyDateTime->isa($DATE_TIME_CLASS) );
              };

            #---- Try DateTime::Format::DateManip for any string
            ($date_str) && do {
                $log->debug( 'Try parsing using DateTimeFormatDateManip : '
                      . $date_str );
                $MyDateTime =

                  $self->_parser_manip( { date_str => $date_str } );

                last SWITCH
                  if ( $MyDateTime && $MyDateTime->isa($DATE_TIME_CLASS) );
            };

            #---- Try DateTime::Format::Natural for any string
            ($date_str) && do {
                $log->debug( 'It may be a Natural Date Format : ' . $date_str );
                $MyDateTime =
                  $self->_parser_natural( { date_str => $date_str } );
                last SWITCH;
            };

          };    #--- End NonEmptyStr Check
    }    #--- End SWITCH

    #------ Return the new DateTime Object in DateTime Format
    $log->debug(
        'Convert_to_datetime generated : ' . ( ($MyDateTime) // $EMPTY ) );
    return $MyDateTime;
}

#-------------------------------------------------------------------------------
#                       DATE PARSING
#-------------------------------------------------------------------------------

#----- Check for content, which is also untainted before parsing
for my $parse_method (
    qw/_parse_date_yyyymmdd _parse_date_mmddyyyy _parse_date_ddmmyyyy
    _parse_hms_am_or_pm _parse_iso_datetime_str /
  )
{
    before $parse_method => sub {
        my $self = shift;
        $self->_str_has_untainted_content_or_confess(shift);
    };
}

=head2 _parse_date_yyyymmdd
  Parse yyyymmdd with Regexp common YMD.
  Returns a HashRef with the parsed date elements or $FAIL.

=cut

sub _parse_date_yyyymmdd {
    my $self     = shift;
    my $date_str = shift;

    #------ YMD
    if ( $date_str =~ $RE{time}{ymd}{-keep} ) {
        my %mover_date_h = (
            year  => $2,
            month => $3,
            day   => $4,
        );

        $log->debug(
            'Extracted the date at parse_date_yyyymmdd: ' . ( $1 // $EMPTY ) );
    }
    return $FAIL;
}

=head2 _parse_date_mmddyyyy
 Parse date MMDDYYYY USA style,  using Regexp common.
 Returns a HashRef with the parsed date elements or $FAIL.

=cut

sub _parse_date_mmddyyyy {
    my $self     = shift;
    my $date_str = shift;

    if ( $date_str =~ $RE{time}{mdy}{-keep} ) {
        my %mover_date_h = (
            month => $2,
            day   => $3,
            year  => $4,
        );
        $log->debug(
            'Extracted the date at parse_date_mmddyyyy ' . ( $1 // $EMPTY ) );
        return \%mover_date_h;
    }
    return $FAIL;
}

=head2 _parse_date_ddmmyyyy
 Parse date ddmmyyyy European style ,  using Regexp common
 Returns a HashRef with the parsed date elements.

=cut

sub _parse_date_ddmmyyyy {
    my $self     = shift;
    my $date_str = shift;

    if ( $date_str =~ $RE{time}{dmy}{-keep} ) {
        my %mover_date_h = (
            day   => $2,
            month => $3,
            year  => $4,
        );

        $log->debug(
            'Extracted the date at parse_date_ddmmyyyy ' . ( $1 // $EMPTY ) );
        return \%mover_date_h;
    }
    return $FAIL;
}

#-------------------------------------------------------------------------------

=head2 _parse_hme_am_or_pm
 Parse to HashRef Hours Minutes and OPtionally Seconds and AM or PM from a string
 Returns a HashRef with the parsed time elements or $FAIL.

=cut

sub _parse_hms_am_or_pm {
    my $self     = shift;
    my $time_str = shift;

    if ( $time_str =~ $RE{time}{hms}{-keep} ) {
        my %mover_time_h = (
            hour     => $2,
            minute   => $3,
            second   => $4 // undef,
            am_or_pm => ( $5 ? uc($5) : undef ),
        );

        $log->debug(
            'Extracted the date at parse_hms_am_or_pm ' . ( $1 // $EMPTY ) );
        return \%mover_time_h;
    }
    return $FAIL;
}

=head2  _parse_iso_datetime_str
 Parse date time elements from date string in ISO-8601 format
 Passed a string in ISO-8601 format YYYY-MM-DDTHH:MM:SS

  $mover_date_href =
  $parse_iso_datetime_str(' some rubbish plus 1970-12-25T09:15:22 ');

 $mover_date_href->{year}  # 1970
 $mover_date_href->{month} # 12
 $mover_date_href->{day}   # 25
 $mover_date_href->{hour}  # 09
 $mover_date_href->{minute} # 15
 $mover_date_href->{second}  # 22

 Returns a HashRef with the parsed date time elements or $FAIL.

=cut

sub _parse_iso_datetime_str {
    my $self     = shift;
    my $date_str = shift;
    ### Iso string is : $date_str
    if ( $date_str =~ $RE{time}{iso}{-keep} ) {
        return {
            year   => $2,
            month  => $3,
            day    => $4,
            hour   => $5 // 0,
            minute => $6 // 0,
            second => $7 // 0,
        };
    }

    return $FAIL;
}

#-------------------------------------------------------------------------------
#                       DATE FORMATTING
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
#  Method Modifiers
#-------------------------------------------------------------------------------
#------ Clean the input to the date formatters
for my $format_method (
    qw/ _format_iso_string_to_datetime_tz
    _format_yyyymmdd_to_datetime_tz
    _format_yyyymmdd_to_datetime_tz
    _format_hashref_to_datetime
    _parser_manip/
  )
{
    around $format_method => sub {
        my $orig = shift;
        my $self = shift;
        my $clean_params =
          $self->_hashref_has_untainted_content_or_confess(shift);
        return $self->$orig($clean_params);
    };
}

=head2 _format_iso_string_to_datetime_tz
 Regexp Common Format Iso string to DateTime with Time Zone
 Pass an ISO String and time zone.
 If no time zone passed, then it defaults to UTC time zone
 Sample string "2012-12-04T20:03:00z"
 Uses Regexp::Common
 Return the formatted DateTime object with time zone
 Will not format an imperfect Iso string.

 my $MyDateTime = _format_iso_string_to_datetime_tz(
    {date_str  => "2012-12-04T20:03:00z"',  time_zone => $UTC_TZ});

=cut

sub _format_iso_string_to_datetime_tz {
    my $self   = shift;
    my $params = shift;
    my $IsoDt;
    try {
        my $date_href = $self->_parse_iso_datetime_str( $params->{date_str} );
        $date_href->{time_zone} = $params->{time_zone} // $UTC_TZ;
        $IsoDt = $self->_format_hashref_to_datetime($date_href);
    }
    catch {
        $log->error(
            'Format_iso_string_to_datetime_tz failed ' . $params->{date_str} );
        $log->error( 'Format error message ' . $_ );
    };

    return $IsoDt;
}

=head2 _format_yyyymmdd_to_datetime_tz 
       _format_ddmmyyyy_to_datetime_tz
       _format_mmddyyyy_to_datetime_tz
 Regexp Common Fortmat yyyymmdd string to DateTime with Time Zone
                       mmddyyyy string to DateTime with Time Zone
                       ddmmyyyy string to DateTime with Time Zone
 Pass a string containint a date in yyyymmdd format
 Pass a time_zont or it will default to UTC.
 Returns DateTime object or $FAIL.

 my $MyDateTime = format_yyyymmdd_to_datetime_tz(
    {date_str  => '1979/12/25',  time_zone => $UTC_TZ});

=cut

sub _format_yyyymmdd_to_datetime_tz {
    my $self   = shift;
    my $params = shift;
    ### yyyymmdd string is :  $params->{date_str}
    my $MyDateTime;
    try {
        my $date_href = $self->_parse_date_yyyymmdd( $params->{date_str} );
        $date_href->{time_zone} = $params->{time_zone} // $UTC_TZ;
        $MyDateTime = $self->_format_hashref_to_datetime($date_href);
    }
    catch {
        $log->error( 'Format_yyyymmdd_string_to_datetime_tz failed '
              . $params->{date_str} );
        $log->error( 'Format error message ' . $_ );
    };

    return $MyDateTime;
}

#------ Format mmddyyyy to DateTime
sub _format_mmddyyyy_to_datetime_tz {
    my $self   = shift;
    my $params = shift;
    ### mmddyyyy string is :  $params->{date_str}
    my $MyDateTime;
    try {
        my $date_href = $self->_parse_date_mmddyyyy( $params->{date_str} );
        $date_href->{time_zone} = $params->{time_zone} // $UTC_TZ;
        $MyDateTime = $self->_format_hashref_to_datetime($date_href);
    }
    catch {
        $log->error( 'Format_mmddyyyy_string_to_datetime_tz failed '
              . $params->{date_str} );
        $log->error( 'Format error message ' . $_ );
    };

    return $MyDateTime;
}

#------ Format ddmmyyyy to DateTime
sub _format_ddmmyyyy_to_datetime_tz {
    my $self   = shift;
    my $params = shift;
    $log->debug( 'Formatting ddmmyyyy ' . $params->{date_str} );
    my $MyDateTime;
    try {
        my $date_href = $self->_parse_date_ddmmyyyy( $params->{date_str} );
        $date_href->{time_zone} = $params->{time_zone} // $UTC_TZ;
        $MyDateTime = $self->_format_hashref_to_datetime($date_href);
    }
    catch {
        $log->error( 'Format_ddmmyyyy failed ' . $params->{date_str} );
        $log->error( 'Format error message ' . $_ );
    };

    return $MyDateTime;
}

#-------------------------------------------------------------------------------

=head2 _format_hashref_to_datetime
 Format a hashref to a DateTime Object
 Convert a HashRef to a DateTime Obj
 Pass the HashRef with Date Time elements
 my $MyDateTime = $format_hashref_to_datetime(
 {
     year      => $year,
     month     => $month,
     day       => $day,
     hour      => $hour,
     minute    => $minute,
     second    => $second,
  },  $UTC_TZ);

=cut

#-------------------------------------------------------------------------------
sub _format_hashref_to_datetime {
    my $self       = shift;
    my $date_href  = shift;
    my $MyDateTime = try {
        DateTime->new(
            year      => $date_href->{year},
            month     => $date_href->{month},
            day       => $date_href->{day},
            hour      => $date_href->{hour} // 0,
            minute    => $date_href->{minute} // 0,
            second    => $date_href->{second} // 0,
            time_zone => $date_href->{time_zone} // $UTC_TZ,
        );
    }
    catch {
        $log->error( 'Failed to format HashRef ' . ( dump $date_href ) );
        $log->error( 'Format error message ' . $_ );
        return $FAIL;
    };
    return $MyDateTime;
}

#-------------------------------------------------------------------------------
#                   Using The Big Guns
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
#                          DateTime::Format::Natural
#-------------------------------------------------------------------------------

=head2  _parser_manip
 Format a string into a DateTime Object using 
 DateTime::Format::DateManip
 Returns DateTime object or $FAIL.
 Converts to a time zone,  if a time_zone parameter is passed to the method.

 my $MyDateTime = _parser_manip(
     {date_str  => '   January 1st,  2001 ',  time_zone => $UTC_TZ});

=cut

sub _parser_manip {
    my $self   = shift;
    my $params = shift;
    ### String for DateManip is :  $params->{date_str}
    my $MyDateTime = try {
        require DateTime::Format::DateManip;
        my $Dt =
          DateTime::Format::DateManip->parse_datetime( $params->{date_str} );
        $Dt->set_time_zone( $params->{time_zone} )
          if (  ( exists $params->{time_zone} )
            and ( defined $params->{time_zone} ) );
        return $Dt;
    }
    catch {
        $log->error(
            'Failed to format with DateManip ' . ( dump $params->{date_str} ) );
        $log->error( 'Format error message ' . $_ );
        $FAIL;
    };

    return $MyDateTime;
}

=head2  _parser_natural
 Format a natural language string into a DateTime Obj
 Uses DateTime::Format::Natural
 Pass the String eg "tomorrow at noon" "Friday evening" etc
 as a named Paramater HashRef ( {date_str => "Friday  Evening"})
 Returns the DateTime object to represent this time.
 Or else it returns Fail

=cut

sub _parser_natural {

    my $self   = shift;
    my $params = shift;
    ### Input Href to parser_natural : $params
    my $NatFormatter = $self->_create_natural_formatter();
    my $DateTime     = try {
        $NatFormatter->parse_datetime( $params->{date_str} );
        return $NatFormatter if $NatFormatter->success();
        ### Date Natural No Comprende : $params->{date_str}
        return undef;
    }
    catch {
        $log->error( 'Failed to format with DateTime::Format::Natural '
              . ( dump $params->{date_str} ) );
        $log->error( 'Format error message ' . $_ );
        $FAIL;
    };
    return $DateTime;
}

=head2 _create_natural_formatter
 Create a DateTime::Format::Natural Object
 Returns the DateTime::Format::Natural object formatter
 Or else it returns Fail
 Uses the UTC time zone

=cut

sub _create_natural_formatter {
    my $self = shift;

    my $NaturalFormatter = try {
        require DateTime::Format::Natural;
        DateTime::Format::Natural->new(
            lang => mover_language(),    # Only handles 'en' at this time
            time_zone => $self->mover_tz() // $UTC_TZ,

            #   For ambigious day references
            prefer_future => $self->mover_future(),

            #--- What Mover considers these start times to be
            daytime => {
                morning   => $self->mover_morning(),
                afternoon => $self->mover_afternoon(),
                evening   => $self->mover_evening(),
            }
        );

    }
    catch {
        $log->error('Failed create with DateTime::Format::Natural ');
        $log->error( 'Reason ' . $_ );
        $FAIL;
    };
    return $NaturalFormatter;
}

#-------------------------------------------------------------------------------
#  Generic Private Helper Methods
#  Mainly for error handling.
#-------------------------------------------------------------------------------

=head2 _str_has_untainted_content_or_confess
 Checks a string for tainted data. Confess and exit if ther is.

=cut

sub _str_has_untainted_content_or_confess {
    my $self = shift;
    confess('Empty date string passed to Convert::Input::To::DateTime!')
      unless ( hascontent $_[0] );
    confess('Tainted date string passed to Convert::Input::To::DateTime!')
      if ( tainted $_[0] );
    return $_[0];
}

=head2 _hashref_has_untainted_content_or_confess
 Checks a HashRef for tainted data. Confess and exit if there is.

=cut

sub _hashref_has_untainted_content_or_confess {
    my $self = shift;
    confess('Empty date hashref passed !')
      unless ( hascontent $_[0] );
    confess('Tainted  or Not a HashRef passed!')
      if ( ( tainted $_[0] ) or ( ref( $_[0] ) ne 'HASH' ) );
    my $hash_ref = shift;
    my %clean_hash;

    foreach my $key ( keys %$hash_ref ) {

        confess('Tainted hashref key sent to Mover::Date!') if ( tainted $key);
        confess('Tainted hashref value sent to Mover::Date!')
          if ( tainted $hash_ref->{$key} );
        $clean_hash{ trim($key) } = trim( $hash_ref->{$key} );

    }
    return \%clean_hash;
}

#-------------------------------------------------------------------------------
#  END
#-------------------------------------------------------------------------------
#no Moose;
#__PACKAGE__->meta->make_immutable;
1;    # End of Convert::Input::To::DateTime
__END__

=head1 NAME

Convert::Input::To::DateTime - Role to convert input data to a DateTime object.

=head1 VERSION

Version 0.01

=cut


=head1 SYNOPSIS

package My::AnyModule;
use Moose;

with 'Convert::Input::To::DateTime';
#------ Input date in string, hashref, DateTime format.
my $DateTime = $self->convert_to_datetime($input_date);


=head1 AUTHOR

Austin Kenny, C<< <aibistin.cionnaith at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-convert-input-to-datetime at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Convert-Input-To-DateTime>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Convert::Input::To::DateTime


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Convert-Input-To-DateTime>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Convert-Input-To-DateTime>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Convert-Input-To-DateTime>

=item * Search CPAN

L<http://search.cpan.org/dist/Convert-Input-To-DateTime/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2013 Austin Kenny.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut


