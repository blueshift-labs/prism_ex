ExUnit.start()

{:ok, _pid} =
  Application.get_all_env(:prism_ex)
  |> PrismEx.start_link()

# Test.Support.Reporter.attach()
