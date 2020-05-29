# Import all plugins from `rel/plugins`
# They can then be used by adding `plugin MyPlugin` to
# either an environment, or release definition, where
# `MyPlugin` is the name of the plugin module.
~w(rel plugins *.exs)
|> Path.join()
|> Path.wildcard()
|> Enum.map(&Code.eval_file(&1))

use Distillery.Releases.Config,
    # This sets the default release built by `mix distillery.release`
    default_release: :default,
    # This sets the default environment used by `mix distillery.release`
    default_environment: Mix.env()

# For a full list of config options for both releases
# and environments, visit https://hexdocs.pm/distillery/config/distillery.html


# You may define one or more environments in this file,
# an environment's settings will override those of a release
# when building in that environment, this combination of release
# and environment configuration is called a profile

environment :dev do
  # If you are running Phoenix, you should make sure that
  # server: true is set and the code reloader is disabled,
  # even in dev mode.
  # It is recommended that you build with MIX_ENV=prod and pass
  # the --env flag to Distillery explicitly if you want to use
  # dev mode.
  set dev_mode: true
  set include_erts: false
  set cookie: :"8y|aIx=xQ|1$Ip73CXG>HJz5@kWhR~OyzS?>_en(asysESIrl76Tr0H*RHV@LXK%"
end

environment :prod do
  set include_erts: true
  set include_src: false
  set cookie: :"c$^t~i5q@BHl>tHN;!*@d_n|!h|6n0~f)6q{Qk1Eg(IUJ$YH_oFUE_RCRGjGI3%G"
  set vm_args: "rel/vm.args"
  set config_providers: [
    {Distillery.Releases.Config.Providers.Elixir, ["${RELEASE_ROOT_DIR}/etc/runtime_config.exs"]}
  ]
  set overlays: [
    {:copy, "rel/runtime_config.exs", "etc/runtime_config.exs"}
  ]
end

# You may define one or more releases in this file.
# If you have not set a default release, or selected one
# when running `mix distillery.release`, the first release in the file
# will be used by default

release :uniris_node do
  set version: System.fetch_env!("VERSION")
  set applications: [
    :runtime_tools,
    uniris_core: :permanent,
    uniris_web: :permanent
  ]
end

