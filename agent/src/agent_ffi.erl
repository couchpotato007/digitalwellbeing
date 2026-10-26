-module(agent_ffi).
-export([os_name/0]).

os_name() ->
    case os:type() of
        {unix, linux} -> linux_name();
        {unix, darwin} ->
            case string:trim(os:cmd("sw_vers -productVersion")) of
                "" -> <<"macOS">>;
                Version -> unicode:characters_to_binary(["macOS ", Version])
            end;
        {win32, _} ->
            %% Windows 11 still reports version 10.0, from build 22000 on
            case os:version() of
                {10, 0, Build} when Build >= 22000 -> <<"Windows 11">>;
                {10, 0, _} -> <<"Windows 10">>;
                _ -> <<"Windows">>
            end;
        {_, Name} -> atom_to_binary(Name)
    end.

%% PRETTY_NAME from /etc/os-release, like "NixOS 25.05 (Warbler)"
linux_name() ->
    case file:read_file("/etc/os-release") of
        {ok, Release} ->
            Lines = binary:split(Release, <<"\n">>, [global]),
            case [Value || <<"PRETTY_NAME=", Value/binary>> <- Lines] of
                [Value | _] -> string:trim(Value, both, "\"'");
                [] -> <<"Linux">>
            end;
        {error, _} -> <<"Linux">>
    end.
