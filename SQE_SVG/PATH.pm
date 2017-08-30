package SQE_SVG::PATH;
use strict;
use warnings FATAL => 'all';
use Math::Complex;

sub new {
    my $class = shift;
    my $self  = bless {
        svg_source_path => shift,
        svg_path        => '',
        lastX           => 0,
        lastY           => 0,
        lastControlX    => 0,
        lastControlY    => 0,
        startX          => 0,
        startY          => 0,
        points          => [],
        test_points     => '',
    }, $class;
    $self->calculate_points;
    return $self;
}

sub svg_path {
    my $self = shift;
    my $out  = '';
    foreach my $points ( @{ $self->{points} } ) {
        $out .= 'M' . join( ' ', @$points );
    }
    return $out;
}

sub calculate_points {
    my $self            = shift;
    my $svg_source_path = $self->{svg_source_path};
    my $points;
    $svg_source_path =~ s/[\n\r]/ /gmo;
    $svg_source_path =~ s/ *([MmLlHhVvAaQqTtCcSsZz]) */:$1:/go;
    $svg_source_path =~ s/[-] */ -/go;
    $svg_source_path =~ s/ +/ /go;
    my @path_elements = split( /:/, $svg_source_path );

    for ( my $i = 1 ; $i < @path_elements ; $i++ ) {
        my $element = $path_elements[ $i++ ];
        if ( uc($element) ne 'Z' ) {
            my $data = [ split( / /, $path_elements[$i] ) ];
            shift @$data while ( defined $data->[0] ) && $data->[0] eq '';
            if ( $element eq 'M' || $element eq 'L' ) {
                $self->_set_last_point_from_data($data);
                if ( $element eq 'M' ) {
                    push $self->{points}, $points if defined $points;
                    $points         = [];
                    $self->{startX} = $self->{lastX};
                    $self->{startY} = $self->{lastY};
                    $self->{test_points} .=
                        '<circle style="stroke:red" cx="'
                      . $self->{lastX}
                      . '" cy="'
                      . $self->{lastY}
                      . '" r="10"/>';
                }
                push $points, @$data;

#                $self->{test_points} .= '<circle style="stroke:yellow" cx="' . $self->{lastX} . '" cy="' . $self->{lastY} . '" r="10"/>';

            }
            elsif ( $element eq 'm' || $element eq 'l' ) {
                $self->_move_points($data);
                if ( $element eq 'm' ) {
                    push $self->{points}, $points if defined $points;
                    $points         = [];
                    $self->{startX} = $self->{lastX};
                    $self->{startY} = $self->{lastY};

#                 print "m: $self->{startX} / $self->{startY}\n";
#                  $self->{test_points} .= '<circle style="stroke:green" cx="' . $self->{lastX} . '" cy="' . $self->{lastY} . '" r="10"/>';
                }
                push $points, @$data;

#                $self->{test_points} .= '<circle style="stroke:yellow; fill:none" cx="' . $self->{lastX} . '" cy="' . $self->{lastY} . '" r="10"/>';

            }
            elsif ( $element eq 'H' ) {
                $self->{lastX} += $data->[0];
                push $points, ( $self->{lastX}, $self->{lastY} );
            }
            elsif ( $element eq 'h' ) {
                $self->{lastX} += $self->_add_values($data);
                push $points, ( $self->{lastX}, $self->{lastY} );
            }
            elsif ( $element eq 'V' ) {
                $self->{lastY} += $data->[0];
                push $points, ( $self->{lastX}, $self->{lastY} );
            }
            elsif ( $element eq 'v' ) {
                $self->{lastY} += $self->_add_values($data);
                push $points, ( $self->{lastX}, $self->{lastY} );
            }

#           elsif (uc($element) eq 'Q') {
#               my ($startX, $startY, @data) = $self->_prepare_data($element, $data);
#               my $i = 0;
#               $self->{svg_path} .= 'L';
#               while ($i < @data) {
#                   $self->{svg_path} .= $self->_calculate_quad_bezier_points($startX, $startY, @data[$i .. $i + 3]);
#                   $startX = $data[$i + 2];
#                   $startY = $data[$i + 3];
#                   $i += 4;
#               }
#               chomp $self->{svg_path};
#           }
            elsif ( uc($element) eq 'C' ) {
                $self->_run_cube_bezier( $element, $data, $points );

            }

            elsif ( uc($element) eq 'S' ) {
                my ( $x, $y ) = $self->_reflect_last_control;
                unshift @$data, ( 0, 0 );
                if ( $element eq 's' ) {
                    $self->_move_points_for_bezier( $data, 1 );
                }
                $data->[0] = $x;
                $data->[1] = $y;
                $self->_run_cube_bezier( 'C', $data, $points );

            }
            else {
                print "$element\n";
            }
        }
        else {
            push $points, ( $self->{startX}, $self->{startY} );

#          $self->{points} .= '<circle transform="move(5,5)" style="stroke:blue; fill:none" cx="' . $self->{lastX} . '" cy="' . $self->{lastY} . '" r="10"/>';

        }
    }
    push $self->{points}, $points if defined $points;

}

sub _run_cube_bezier {
    my ( $self, $element, $data, $points ) = @_;
    if ( $element ne 'C' ) {
        $self->_move_points_for_bezier( $data, 1 );
    }
    else {
        $self->_set_last_point_from_data($data);
    }
    my ( $startX, $startY ) = ( $self->{startX}, $self->{startY} );
    my $i = 0;
    while ( $i < @$data ) {
        push @$points,
          $self->_calculate_cube_bezier_points( $startX, $startY,
            @$data[ $i .. ( $i + 5 ) ] );
        $startX = $data->[ $i + 4 ];
        $startY = $data->[ $i + 5 ];
        $i += 6;
    }

}

sub _calculate_coord_quad_bezier {
    my ( $start, $control, $end, $step ) = @_;
    return ( ( 1 - $step )**2 ) * $start +
      2 * $step * ( 1 - $step ) * $control +
      ( $step**2 ) * $end;
}

sub _calculate_quad_bezier_points {
    my ( $self, $startX, $startY, $controlX, $controlY, $endX, $endY ) = @_;

    my $dertour_distance =
      sqrt( ( $controlX - $startX )**2 + ( $controlY - $startY )**2 ) +
      sqrt( ( $endX - $controlX )**2 +   ( $endY - $controlY )**2 ) -
      sqrt( ( $startX - $endX )**2 +     ( $startY - $endY )**2 );
    if ( $dertour_distance < 2 ) {
        return "$controlX $controlY $endX $endY";
    }
    else {
        my $step     = 1 / $dertour_distance / 2;
        my $distance = $step;
        my $out      = '';
        while ( $distance < 1 ) {
            $out .=
              _calculate_coord_quad_bezier( $startX, $controlX, $endX,
                $distance )
              . ' ';
            $out .=
              _calculate_coord_quad_bezier( $startY, $controlY, $endY,
                $distance )
              . ' ';
            $distance += $step;
        }
        return $out;
    }
}

sub _calculate_coord_cube_bezier {
    my ( $start, $control_1, $control_2, $end, $step ) = @_;
    return ( ( 1 - $step )**3 ) * $start +
      3 * $step * ( ( 1 - $step )**2 ) * $control_1 +
      3 * ( 1 - $step ) * ( $step**2 ) * $control_2 +
      ( $step**3 ) * $end;
}

sub _reflect_last_control {
    my $self = shift;
    return (
        2 * $self->{lastX} - $self->{lastControlX},
        2 * $self->{lastY} - $self->{lastControlY}
    );
}

sub _calculate_cube_bezier_points {
    my (
        $self,       $startX,     $startY, $controlX_1, $controlY_1,
        $controlX_2, $controlY_2, $endX,   $endY
    ) = @_;

#    $self->{test_points} .= '<circle style="stroke:green; fill:none" cx="' . $startX . '" cy="' . $startY . '" r="10"/>';
#   $self->{test_points} .= '<circle style="stroke:red; fill:none" cx="' . $endX . '" cy="' . $endY . '" r="10"/>';

    $self->{lastControlX} = $controlX_2;
    $self->{lastControlY} = $controlY_2;
    my $dertour_distance =
      sqrt( ( $controlX_1 - $startX )**2 + ( $controlY_1 - $startY )**2 ) +
      sqrt(
        ( $controlX_2 - $controlX_1 )**2 + ( $controlY_2 - $controlY_1 )**2 ) +
      sqrt( ( $endX - $controlX_2 )**2 + ( $endY - $controlY_2 )**2 ) -
      sqrt( ( $startX - $endX )**2 + ( $startY - $endY )**2 );
    if ( $dertour_distance < 1 ) {
        return "$controlX_1 $controlY_1 $controlX_2 $controlY_2 $endX $endY";
    }
    else {
        my $step = 1 / $dertour_distance / 0.1;

        #        my $step=0.1;
        my $distance = $step;
        my @points   = ();
        while ( $distance < 1 ) {
            my $x =
              _calculate_coord_cube_bezier( $startX, $controlX_1, $controlX_2,
                $endX, $distance );
            my $y =
              _calculate_coord_cube_bezier( $startY, $controlY_1, $controlY_2,
                $endY, $distance );
            push @points, ( $x, $y );

#           $self->{test_points} .= '<circle style="stroke:red; fill:none" cx="' . $x . '" cy="' . $y . '" r="3"/>';

            $distance += $step;

        }
        push @points, ( $endX, $endY );
        return @points;
    }
}

sub _prepare_data {
    my $self    = shift;
    my $element = shift;
    my $data    = shift;
    my $startX  = $self->{lastX};
    my $startY  = $self->{lastY};
    if ( uc($element) ne $element ) {
        $data = $self->_move_points_for_bezier($data);
    }
    else {
        $self->_set_last_point_from_data($data);
    }
    my @data = split( / /, $data );
    shift @data while ( $data[0] eq '' );
    return ( $startX, $startY, @data );

}

sub _set_last_point_from_data {
    my ( $self, $data ) = @_;
    my $last = $#$data;
    $self->{lastX} = $data->[ $last - 1 ];

    $self->{lastY} = $data->[$last];
}

sub _move_points_for_bezier {
    my ( $self, $data, $is_cube ) = @_;
    my ( $startX, $startY ) = ( $self->{lastX}, $self->{lastY} );
    $self->{startX} = $startX;
    $self->{startY} = $startY;
    my $i = 0;
    while ( $i < @$data ) {
        $data->[ $i++ ] += $startX;
        $data->[ $i++ ] += $startY;
        if ($is_cube) {
            $data->[ $i++ ] += $startX;
            $data->[ $i++ ] += $startY;
        }
        $data->[$i] += $startX;
        $startX = $data->[ $i++ ];
        $data->[$i] += $startY;
        $startY = $data->[ $i++ ];
    }
    $self->{lastX} = $startX;
    $self->{lastY} = $startY;

}

sub _move_points {
    my ( $self, $data ) = @_;
    for ( my $i = 0 ; $i < @$data ; $i++ ) {
        $data->[$i] += $self->{lastX};
        $self->{lastX} = $data->[ $i++ ];
        $data->[$i] += $self->{lastY};
        $self->{lastY} = $data->[$i];
    }
}

sub _add_values {
    my ( $self, $data ) = @_;
    my $value = 0;
    map { $value += $_ } @$data;
    return $value;
}

{

    package SQE_SVG::PATH::Single;

    sub new {
        my $class = shift;
        my $self  = bless {
            x_values    => [],
            y_values    => [],
            max_x       => 0,
            max_x_index => 0,
            max_y       => 0,
            max_y_index => 0,
            min_x       => 0,
            min_x_index => 0,
            min_y       => 0,
            min_y_index => 0,
            dirty       => 1,

        }, $class;

        return $class;
    }

    sub add_point {
        my ( $self, $x, $y ) = @_;
        push $self->{x_values}, $x;
        push $self->{x_values}, $y;
        $self->{dirty}=1;
    }

    sub close_path {
        my $self = shift;
        push $self->{x_values}, $self->{x_values}->[0];
        push $self->{x_values}, $self->{y_values}->[0];
    }

    sub analyze {
        my $self = shift;
        if ($self->{dirty}==1) {
            $self->{max_x} = $self->{max_y} = $self->{max_y} = $self->{min_y} = 0;
            for (my $i = 0; $i < @{ $self->{x_values} }; $i00) {
                if ($self->{$x_values}->[$i] > $self->{max_x}) {
                    $self->{max_x} = $self->{x_values}->[$i];
                    $self->{max_x_index} = $i;
                }
                elsif ($self->{$x_values}->[$i] < $self->{min_x}) {
                    $self->{min_x} = $self->{x_values}->[$i];
                    $self->{min_x_index} = $i;
                }
                if ($self->{$y_values}->[$i] > $self->{max_y}) {
                    $self->{max_y} = $self->{y_values}->[$i];
                    $self->{max_y_index} = $i;
                }
                elsif ($self->{$y_values}->[$i] < $self->{min_y}) {
                    $self->{min_y} = $self->{y_values}->[$i];
                    $self->{min_y_index} = $i;
                }
            }
        }
        $self->{dirty}=0;
    }

    sub move_to_origin {
        my $self = shift;
        for ( my $i = 0 ; $i < @{ $self->{x_values} } ; $i00 ) {
            $self->{x_values}->[$i] -= $self->{min_x};
            $self->{y_values}->[$i] -= $self->{min_y};
        }
        $self->{max_x} -= $self->{min_x};
        $self->{max_y} -= $self->{min_y};
        $self->{max_x} = 0;
        $self->{min_x} = 0;
    }

    sub flip_vertically {
        my $self = shift;
        for ( my $i = 0 ; $i < @{ $self->{x_values} } ; $i00 ) {
            $self->{y_values}->[$i] = $self->{max_y} - $self->{y_values}->[$i];
        }

    }
}

1;

