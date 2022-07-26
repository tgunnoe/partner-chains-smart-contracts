import json
import os
import string
import subprocess
import tempfile
from os.path import (splitext, exists)
from functools import cache
from typing import List

MAINNET_MAGIC=764824073

## General python Operations

def option_then(o, f):
    return o and f(o)

def on_ok(result, override):
    status, payload = result
    if status == 'ok':
        return status, override(payload)
    else:
        return result

@cache
def getenv(extra_paths : List = []): # '/nix/store/lay4bvzmlknbr1h6ph4bc1bhnww9gbdg-devshell-dir/bin/'
    env = { **os.environ }
    extra_paths.append(env['PATH'])
    env['PATH'] = os.pathsep.join(extra_paths)
    return env

def run_cli(command, **kw):
    with subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=getenv(),
        **kw,
    ) as process:
        stdout, stderr = process.communicate()
        stdout = stdout.decode("utf-8")
        stderr = stderr.decode("utf-8")
        if stderr:
            return ('error', stderr)
    try:
        return 'ok', json.loads(stdout)
    except:
        return 'ok', stdout

def write_file(path, content):
    with open(path, 'w') as file:
        file.write(content)
def read_file(path):
    with open(path, 'r') as file:
        return file.read()

## Cardano cli and other Tools

@cache
def get_address(vkey_path, magic, type='verification-key'):
    cmd = [
        'cardano-cli', 'address', 'build',
        '--mainnet' if magic == MAINNET_MAGIC else f'--testnet-magic={magic}',
        f'--payment-{type}-file={vkey_path}',
    ]
    return run_cli(cmd)

@cache
def get_params_file(magic):
    with tempfile.NamedTemporaryFile(prefix='trustless-sidechain-', suffix='.json', delete=False) as fd:
        cmd = [
            'cardano-cli', 'query', 'protocol-parameters',
            '--mainnet' if magic == MAINNET_MAGIC else f'--testnet-magic={magic}',
            f'--out-file={fd.name}',
        ]
        return on_ok(run_cli(cmd), lambda _: fd.name)


def mk_vkey(skey_path):
    vkey_path = splitext(skey_path)[0] + '.vkey'
    if exists(vkey_path):
        return ('ok', vkey_path)
    else:
        cmd = [
            'cardano-cli', 'key', 'verification-key',
            f'--signing-key-file={skey_path}',
            f'--verification-key-file={vkey_path}',
        ]

        return on_ok(run_cli(cmd), lambda _: vkey_path)

def get_own_pkh(vkey_path):
    cmd = [
        'cardano-cli', 'address', 'key-hash',
        f'--payment-verification-key-file={vkey_path}'
    ]
    
    return on_ok(run_cli(cmd), lambda x: x.strip())

def get_utxos(addr, magic):
    with tempfile.NamedTemporaryFile(prefix='trustless-sidechain-', suffix='.json') as fd:
        cmd = [
            'cardano-cli', 'query', 'utxo',
            '--mainnet' if magic == MAINNET_MAGIC else f'--testnet-magic={magic}',
            f'--address={addr}',
            f'--out-file={fd.name}'
        ]
        return on_ok(run_cli(cmd), lambda _: json.load(fd))

@cache
def get_project_root():
    path = os.path.realpath(
        os.path.join(__file__, os.path.pardir, os.path.pardir, os.path.pardir)
    )
    assert os.path.exists(os.path.join(path, 'cabal.project')), "got wrong root path for the script" + path
    return path

@cache
def get_value(script, name):
    if name == 'lovelace': return
    cmd = [
        'cardano-cli', 'transaction', 'policyid',
        f'--script-file={script}',
    ]
    status, out = run_cli(cmd)
    assert status == 'ok', out
    name = ''.join([hex(ord(c))[2:] for c in name])
    out = out.strip()
    return f'{out}.{name}'


def export(genesis_tx_in, chain_id, genesis_hash, own_pkh, spo_key, sidechain_key, register_tx_in):
    os.makedirs(os.path.join(get_project_root(), 'exports'), exist_ok=True)
    cmd = [
        'cabal', 'run', 'trustless-sidechain-export', '--',
        f'{genesis_tx_in}', f'{chain_id}', f'{genesis_hash}', f'{own_pkh}',
        f'{spo_key}', f'{sidechain_key}', f'{register_tx_in}'
    ]
    return run_cli(cmd, cwd=get_project_root())

@cache
def exports(file):
    return os.path.join(get_project_root(), 'exports', file)

def build(
        tx_ins: List, # hash#index
        tx_out,       # addr+amount
        tx_coll,      # hash#index
        out_file,     # filepath
        magic,
        era='babbage',
        with_submit=False,
        **kw # in_script, in_datum, in_inline_datum, in_redeemer, out_inline_datum, mint_val, mint_script, mint_redeemer, secret_keyfile
  ):
    status, own_addr = get_address(kw['public_keyfile'], magic)
    assert status == 'ok'
    status, params = get_params_file(magic)
    assert status == 'ok'
    cmd = [
        'cardano-cli', 'transaction', 'build',
        f'--{era}-era',
        '--mainnet' if magic == MAINNET_MAGIC else f'--testnet-magic={magic}',

        option_then(kw.get('in_script'), lambda x: f'--tx-in-script-file={x}'),
        option_then(kw.get('in_datum'), lambda x: f'--tx-in-datum-file={x}'),
        option_then(kw.get('in_inline_datum'), lambda _: f'--tx-in-inline-datum-present'),
        option_then(kw.get('in_redeemer'), lambda x: f'--tx-in-redeemer-file={x}'),
    ]

    for tx_in in tx_ins:
        cmd.append(f'--tx-in={tx_in}')

    cmd += [
        f'--tx-in-collateral={tx_coll}',
        f'--tx-out={tx_out}',

        option_then(kw.get('out_inline_datum'), lambda x: f'--tx-out-inline-datum-file={x}'),

        option_then(kw.get('mint_val'), lambda x: f'--mint={x[0]} {x[1]}'),
        option_then(kw.get('mint_script'), lambda x: f'--mint-script-file={x}'),
        option_then(kw.get('mint_redeemer'), lambda x: f'--mint-redeemer-file={x}'),
        option_then(kw.get('required_signer'), lambda x: f'--required-signer-hash={x}'),

        f'--change-address={own_addr}',
        f'--protocol-params-file={params}',
        f'--out-file={exports(out_file+".raw")}',
    ]

    cmd = [arg for arg in cmd if arg != None] # get rid of null-options

    status, out = run_cli(cmd)

    if with_submit:
        if status == 'ok': status, out = sign(out_file, magic, kw['secret_keyfile'])
        if status == 'ok': status, out = submit(out_file, magic)

    return status, out

def sign(out_file, magic, secret_keyfile=None):
    cmd = [
        'cardano-cli', 'transaction', 'sign',
        '--mainnet' if magic == MAINNET_MAGIC else f'--testnet-magic={magic}',
        f'--tx-body-file={exports(out_file+".raw")}',
        f'--signing-key-file={secret_keyfile}',
        f'--out-file={exports(out_file+".sig")}'
    ]
    return run_cli(cmd)

def submit(out_file, magic):
    cmd = [
        'cardano-cli', 'transaction', 'submit',
        '--mainnet' if magic == MAINNET_MAGIC else f'--testnet-magic={magic}',
        f'--tx-file={exports(out_file+".sig")}',
    ]
    return run_cli(cmd)
