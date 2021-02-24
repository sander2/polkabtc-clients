#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

NUM_VAULTS=${NUM_VAULTS:-5}
EXCHANGE_RATE=${EXCHANGE_RATE:-385523187}
VAULT_AMOUNT=${VAULT_AMOUNT:-100000000000}
VAULT_COLLATERAL=${VAULT_COLLATERAL:-1000000000}

BTC_PARACHAIN_RPC=${BTC_PARACHAIN_RPC:-"ws://localhost:9944"}

VAULT_CLIENT_BIN=${VAULT_CLIENT_BIN:-"${DIR}/../../target/debug/vault"}
TESTDATA_CLIENT_BIN=${TESTDATA_CLIENT_BIN:-"${DIR}/../../target/debug/testdata-gen"}

declare -A dict

keyFile=$(mktemp)

function finish {
  rm $keyFile
  kill -- -$$
}
trap finish EXIT

echo "Setting exchange rate as ${EXCHANGE_RATE}"
${TESTDATA_CLIENT_BIN} --keyring bob --polka-btc-url ${BTC_PARACHAIN_RPC} \
    set-exchange-rate --exchange-rate ${EXCHANGE_RATE}

# populate keyfile
for i in $(seq 1 $NUM_VAULTS); do
    VAULT_NAME="vault-${i}"

    SECRET_KEY=$(subkey generate --output-type json)
    SECRET_PHRASE=$(echo ${SECRET_KEY} | jq .secretPhrase)
    dict[${VAULT_NAME}]=${SECRET_PHRASE}

    ACCOUNT_ID=$(echo ${SECRET_KEY} | jq -r .ss58Address)
    echo "${VAULT_NAME}=${ACCOUNT_ID}"

    # TODO: async this once concurrent signing re-enabled
    ${TESTDATA_CLIENT_BIN} --keyring alice --polka-btc-url ${BTC_PARACHAIN_RPC} \
        transfer-dot --account-id ${ACCOUNT_ID} --amount ${VAULT_AMOUNT}
done

for i in "${!dict[@]}"
do
    echo "\"$i\""
    echo "${dict[$i]}"
done | 
jq -n 'reduce inputs as $i ({}; . + { ($i): input })' > $keyFile

for i in $(seq 1 $NUM_VAULTS); do
    VAULT_NAME="vault-${i}"
    echo "Starting ${VAULT_NAME}"

    ${VAULT_CLIENT_BIN} \
        --polka-btc-url ${BTC_PARACHAIN_RPC} \
        --auto-register-with-collateral ${VAULT_COLLATERAL} \
        --http-addr "[::0]:303$i" \
        --keyfile $keyFile \
        --keyname ${VAULT_NAME} \
        --network regtest &

done

wait