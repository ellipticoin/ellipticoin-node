defmodule RequestHandler do
  def init(request, options) do
    method = :cowboy_req.method(request)
    body = read_body(request)

    reply = case method do
      "POST" ->
        case run(body) do
          {:ok, result} ->
            success(result, request)
          {:error, code, message} ->
            error(code, message, request)
        end

      "PUT" ->
        reply = deploy(body)
        {:ok, reply, options}
      _ ->
        {:error, 501, "Not Implemented"}
    end

    {:ok, reply, options}
  end

  def deploy(<<
    signature::binary-size(64),
    message::binary
    >>) do
      GenServer.call(VM, {:deploy, %{}})
  end

  def read_body(request) do
    {:ok, body, _headers} = :cowboy_req.read_body(request)
    body
  end

  def success(payload, request) do
    :cowboy_req.reply(
      200,
      %{"Content-Type" => "application/cbor"},
      payload,
      request
    )
  end

  def error(code, message, request) do
    :cowboy_req.reply(
      code,
      %{"Content-Type" => "text/plain"},
      message,
      request
    )
  end

  def run(<<
    signature::binary-size(64),
    message::binary
    >>) do

      <<
        sender::binary-size(32),
        nonce::binary-size(4),
        address::binary-size(32),
        contract_id::binary-size(32),
        rpc::binary
      >> = message

      if Crypto.valid_signature?(signature, message, sender) do
        case GenServer.call(VM, {:call, %{
          address: address,
          contract_id: contract_id,
          rpc: rpc,
          sender: sender,
          nonce: nonce,
        }}) do
          {:error, code, message} -> {:error, 400 + code, message}
          response -> response
        end
      else
        {:error, 401, "Invalid signature"}
      end
  end
end
