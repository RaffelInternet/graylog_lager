-module(graylog_lager_gelf_formatter).

-export([
    format/2,
    format/3
]).

-define(GELF_VERSION, <<"1.1">>).

format(Message, Config, _Colors) ->
    format(Message, Config).

format(Message, Config) ->
    do_compression(safe_encode(get_raw_data(Message, Config)), graylog_lager_utils:lookup(compression, Config, disabled)).

% internals

safe_encode(Msg) ->
    case catch jiffy:encode({Msg}, [force_utf8]) of
        JsonPayloadBin when is_binary(JsonPayloadBin) ->
            JsonPayloadBin;
        JsonPayloadList when is_list(JsonPayloadList) ->
            iolist_to_binary(JsonPayloadList);
        {error, _} ->
            {value, {_, InnerMsg}, Msg1} = lists:keytake(<<"short_message">>, 1, Msg),
            InnerMsg2 = iolist_to_binary(io_lib:format("hex msg. json encode failed: ~p", [graylog_hex:bin2hex(term_to_binary(InnerMsg))])),
            safe_encode([{<<"short_message">>, InnerMsg2} | Msg1])
    end.

get_raw_data(Message, Config) ->
    BaseMessage = [
        {<<"version">>, ?GELF_VERSION},
        {<<"level">>, graylog_lager_utils:severity2int(lager_msg:severity(Message))},
        {<<"short_message">>, graylog_lager_utils:term2bin(lager_msg:message(Message))},
        {<<"timestamp">>, graylog_lager_utils:unix_timestamp(lager_msg:timestamp(Message))},
        {<<"host">>, graylog_lager_utils:lookup(hostname, Config)} |
        get_metadata(Message)
    ],

    case graylog_lager_utils:lookup(extra_fields, Config) of
        undefined ->
            BaseMessage;
        Extra when is_list(Extra) ->
            BaseMessage ++ Extra
    end.

get_metadata(Msg) ->
    get_metadata(lager_msg:metadata(Msg), []).

get_metadata([{K, V} | T], Acc) ->
    get_metadata(T, [{<<"_", (graylog_lager_utils:term2bin(K))/binary>>, graylog_lager_utils:term2bin(V)} | Acc]);
get_metadata([], Acc) ->
    Acc.

do_compression(Data, disabled) ->
    Data;
do_compression(Data, gzip) ->
    zlib:gzip(Data);
do_compression(Data, zlib) ->
    zlib:compress(Data).
