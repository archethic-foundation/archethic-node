defmodule GraphqlServerAPI do
  use CommonGraphQLClient.Context,
    otp_app: :archethic

  def subscribe do
    # NOTE: This will call __MODULE__.receive(:employee_created, employee) when data is received
    # client().subscribe_to(:transactionConfirmed, __MODULE__)
  end

  def receive({:transactionConfirmed, _data, from}, response) do
    IO.inspect(response,
      label: "<---------- [response] ---------->",
      limit: :infinity,
      printable_limit: :infinity
    )

    send(from, {:reply, response})
  end

  def receive(subscription, response) do
    IO.inspect(subscription, label: "<---------- [subs from second] ---------->", limit: :infinity, printable_limit: :infinity)
    IO.inspect(response, label: "<---------- [response] ---------->", limit: :infinity, printable_limit: :infinity)
  end
end
