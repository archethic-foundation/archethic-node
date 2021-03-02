#!/usr/bin/env bash

rpc='\
  System.get_env() \
  |> Enum.filter(&String.starts_with?(elem(&1,0), "UNIRIS_")) \
  |> Enum.map(&("#{elem(&1,0)}=#{elem(&1,1)}")) \
  |> Enum.join(";")'

if output="$(release_remote_ctl rpc "$rpc")"
then
  # split by ; cutting quotation and newline
  IFS=";" read -a my_array <<< "${output:1:${#output}-2}"
  for var in "${my_array[@]}"
  do
    info "Clone $var"
    export "$var"
  done
fi
