package SQE_Format::JSON;
use strict;
use warnings FATAL => 'all';

use parent 'SQE_Format::Parent';

use constant {


    ALL_LABLE                     => [ '"text":', '', '', '', '' ],

    SCROLLS_LABLE                  => [ '', '[', ']', '', '' ],

    SCROLL_LABLE                  => [ '', '{', '}', '', '},(' ],
    SCROLL_ID_LABLE               => [ '"scroll_id":', '', ',', '', '' ],
    SCROLL_NAME_LABLE             => [ '"scroll_name":', '"', '",', '', '' ],

    FRAGS_LABLE                    => [ '"fragments":', '[', ']', '', '', '},{' ],


    FRAG_LABLE                    => [ '', '{', '}', '', '},{' ],
    FRAG_ID_LABLE                 => [ '"fragment_id":', '', ',', '', '' ],
    FRAG_NAME_LABLE               => [ '"fragment_name":', '"', '",', '', '' ],

    LINES_LABLE                    => [ '"lines":', '[', ']', '', '', '},{' ],


    LINE_LABLE                    => [ '', '{', '}', '', '', '},{' ],
    LINE_ID_LABLE                 => [ '"line_id":', '', ',', '', '' ],
    LINE_NAME_LABLE               => [ '"line_name":', '"', '",', '', '' ],

    SIGNS_LABLE => ['"signs":', '[', ']', '', '', '},{'],

    SIGN_LABLE                    => [ '', '{', '}', '},{'],
    SIGN_ID_LABLE                 => [ '"sign_id":', '', ',' ],
    NEXT_SIGN_IDS_LABLE           => [ '"next_sign_ids":', '', ',', '[', '],', ',' ],

    CHARS_LABLE                   => [ '"chars":', '{', '}', '[{', '}]', '},{' ],
    SIGN_CHAR_LABLE               => [ '{', '{', '}', '[', ']', ',' ],
    SIGN_CHAR_ID_LABLE            => [ '"sign_char_id":', '', '' ],
    SIGN_CHAR_CHAR_LABLE          => [ ',"sign_char":', '"', '"' ],
    ATTRIBUTES_LABLE              => [ ',"attributes":', '{', '}', '[{', '}]', '},{' ],
    ATTRIBUTE_LABLE               => [ '{', '{', '}', '[', ']', ',' ],
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