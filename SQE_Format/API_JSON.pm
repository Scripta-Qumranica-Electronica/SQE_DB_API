package SQE_Format::API_JSON;
use strict;
use warnings FATAL => 'all';

use parent 'SQE_Format::Parent';

use constant {

    EXCLUDED_ATTRIBUTES => {9=>1},


    ALL_LABLE                     => [ '"VALUE":', '', '', '', '' ],

    SCROLLS_LABLE                  => [ '', '[', ']', '', '' ],

    SCROLL_LABLE                  => [ '', '{', '}', '', '},(' ],
    SCROLL_ID_LABLE               => [ undef, '', ',', '', '' ],
    SCROLL_NAME_LABLE             => [ '"SCROLL":', '"', '",', '', '' ],

    FRAGS_LABLE                    => [ '"FRAGMENTS":', '[', ']', '', '', '},{' ],


    FRAG_LABLE                    => [ '', '{', '}', '', '},{' ],
    FRAG_ID_LABLE                 => [ undef, '', ',', '', '' ],
    FRAG_NAME_LABLE               => [ '"FRAGMENT":', '"', '",', '', '' ],

    LINES_LABLE                    => [ '"LINES":', '[', ']', '', '', '},{' ],


    LINE_LABLE                    => [ '', '{', '}', '', '', '},{' ],
    LINE_ID_LABLE                 => [ undef, '', ',', '', '' ],
    LINE_NAME_LABLE               => [ '"LINE":', '"', '",', '', '' ],

    SIGNS_LABLE => ['"SIGNS":', '[', ']', '', '', '},{'],

    SIGN_LABLE                    => [ '', '{', '}', '},{'],
    SIGN_ID_LABLE                 => [ '"SIGN_ID":', '', ',' ],
    NEXT_SIGN_IDS_LABLE           => [ undef, '', ',', '[', '],', ',' ],

    CHARS_LABLE                   => [ '"chars":', '{', '}', '[{', '}]', '},{' ],
    SIGN_CHAR_LABLE               => [ '{', '{', '}', '[', ']', ',' ],
    SIGN_CHAR_ID_LABLE            => [ '"sign_char_id":', '', '' ],
    SIGN_CHAR_CHAR_LABLE          => [ ',"sign_char":', '"', '"' ],
    ATTRIBUTES_LABLE              => [ ',"attributes":', '{', '}', '[{', '}]', '},{' ],
    ATTRIBUTE_LABLE               => [ '"sign_char_attribute_id":', '', ',', '', '', ',' ],
    ATTRIBUTE_ID_LABLE            => [ '"attribute_id":', '', ',' ],
    ATTRIBUTE_NAME_LABLE          => [ '"attribute_name":', '"', '",' ],
    ATTRIBUTE_VALUE_LABLE         => [ '"values":', '{', '}', '[{', '}]', '},{' ],
    ATTRIBUTE_VALUE_ID_LABLE      => [ '"attribute_value_id":', '', ',' ],
    ATTRIBUTE_STRING_VALUE_LABLE  => [ '"attribute_value":', '"', '"', '["', '"]', '","' ],
    ATTRIBUTE_NUMERIC_VALUE_LABLE =>
        [ '"attribute_value":', '', '', '[', ']', ',' ],
    SIGN_CHAR_COMMENTARY_ID_LABLE=> [ '"commentary_id":', '', ',', '', '' ]

};

1;