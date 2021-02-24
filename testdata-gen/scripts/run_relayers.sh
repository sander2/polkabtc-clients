#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

NUM_RELAYERS=${NUM_RELAYERS:-5}
RELAYER_AMOUNT=${RELAYER_AMOUNT:-100000000000}
RELAYER_STAKE=${RELAYER_STAKE:-100}

BTC_PARACHAIN_RPC=${BTC_PARACHAIN_RPC:-"ws://localhost:9944"}

RELAYER_CLIENT_BIN=${RELAYER_CLIENT_BIN:-"${DIR}/../../target/debug/staked-relayer"}
TESTDATA_CLIENT_BIN=${TESTDATA_CLIENT_BIN:-"${DIR}/../../target/debug/testdata-gen"}

declare -A dict

keyFile=$(mktemp)

function finish {
  rm $keyFile
  kill -- -$$
}
trap finish EXIT

# populate keyfile
for i in $(seq 1 $NUM_RELAYERS); do
    RELAYER_NAME="relayer-${i}"

    SECRET_KEY=$(subkey generate --output-type json)
    SECRET_PHRASE=$(echo ${SECRET_KEY} | jq .secretPhrase)
    dict[${RELAYER_NAME}]=${SECRET_PHRASE}

    ACCOUNT_ID=$(echo ${SECRET_KEY} | jq -r .ss58Address)
    echo "${RELAYER_NAME}=${ACCOUNT_ID}"

    # TODO: async this once concurrent signing re-enabled
    ${TESTDATA_CLIENT_BIN} --keyring alice --polka-btc-url ${BTC_PARACHAIN_RPC} \
        transfer-dot --account-id ${ACCOUNT_ID} --amount ${RELAYER_AMOUNT}
done

for i in "${!dict[@]}"
do
    echo "\"$i\""
    echo "${dict[$i]}"
done | 
jq -n 'reduce inputs as $i ({}; . + { ($i): input })' > $keyFile

for i in $(seq 1 $NUM_RELAYERS); do
    RELAYER_NAME="relayer-${i}"
    echo "Starting ${RELAYER_NAME}"

    ${RELAYER_CLIENT_BIN} \
        --polka-btc-url ${BTC_PARACHAIN_RPC} \
        --auto-register-with-stake ${RELAYER_STAKE} \
        --http-addr "[::0]:304$i" \
        --keyfile $keyFile \
        --keyname ${RELAYER_NAME} &

done

wait