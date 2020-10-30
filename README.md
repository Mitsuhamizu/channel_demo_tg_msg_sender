# channel_demo_tg_msg_sender

It's a tg bot service, which simply means you set up a payment channel with the server, and then exchange ckb for my UDT one to one. then you can have the tg bot send the message you want to send to the group for one udt per character. The idea of GPC is from [talk](https://talk.nervos.org/t/a-generic-payment-channel-construction-and-its-composability/4697). 
Also, you can view the contract codes for [GPC](https://github.com/ZhichunLu-11/ckb-gpc-contract/blob/c8ad9ef42c6dd9e334c5099fa9510cef2997557d/main.c) and [UDT](https://github.com/ZhichunLu-11/ckb-gpc-contract/blob/c8ad9ef42c6dd9e334c5099fa9510cef2997557d/c/simple_udt.c).
## Prerequisites

* [ckb testnet](https://github.com/nervosnetwork/ckb) with rpc listen port 8114.
* [ckb indexer](https://github.com/nervosnetwork/ckb-indexer) with listen port 8116.
* [mongodb](https://github.com/mongodb/mongo)

Please make sure that all of the above services are running and synced to the latest blocks. Then you need to have the following ruby module, and also, and I suggest you use ruby 2.6.

* ckb-ruby-sdk
* Thor
* Mongo

And then execute:

```
$ bundle install
```

## Usage

First you can run
```
cd client
ruby GPC.rb
```
to see all the command. I'm only going to cover the commands you need to run under normal flow here.

### Init client

```
ruby GPC.rb init <Your private key>
```
For example,
```
ruby GPC.rb init 0xd986d7bf901e50368cbe565f239c224934cd554805357338abcef177efadc08d
```
Please don't forget to prefix it with 0x.

### Monitor the chain

```
ruby GPC.rb monitor
```
This is to prevent the other party from cheating and to automatically send settlement transactions.
### Create channel

Then you need to reopen a shell and run 
```
ruby GPC.rb send_establishment_request --funding <quantity>
```
For example, 
```
ruby GPC.rb send_establishment_request --funding ckb:200 udt:0
```
Please note that please follow the format of funding, even if the amount of UDT you want to put in is zero. Then, if the channel is established successfully, you should see 
```
channel is established, please wait the transaction on chain.
```
Once the transaction on chain, you can see in the shell that runs the monitor
```
f119905665a0dea6a3eb6cbdc9bcf75b's fund tx on chain at block number 610468, the tx hash is 0x9f31a56c578047d6bc6714f984b52a9619367eb7acb74e3e7a4403e540d41e57.
```


### List channel

```
ruby GPC.rb list_channel
```
This allows you to see the status of all your channels. For example,
```
channel f119905665a0dea6a3eb6cbdc9bcf75b, with 4 payments and stage is 3
 local's ckb: 80 ckbytes, local's udt 88.
 remote's ckb: 120 ckbytes, remote's udt 1999912.
```

* 'f119905665a0dea6a3eb6cbdc9bcf75b' is the channel id.


### Use channel
From the previous step, you know what the id of the channel is, and then you can set it as the default channel for your interaction with the bot.
```
ruby GPC.rb use_channel --id <id>
```
For example,
```
ruby GPC.rb use_channel --id f119905665a0dea6a3eb6cbdc9bcf75b
```
### Exchange UDT
As you can see, you only put in CKB when you build the channel. to make the process more fun, I made the bot recognize UDT as the only currency. So you first need to exchange for UDT.
```
ruby GPC.rb make_exchange_ckb_to_udt --quantity 20
```
You can replace 20 with any number you want, as long as you have enough CKBs. note that one CKB can only be exchanged for one UDT.
Also, you can trade UDT for CKB, just use make_exchange_udt_to_ckb.

### Send tg msg

At this point, you'll be able to use the payment channel to make UDT payments and have tg bots send your messages.

```
ruby GPC.rb send_tg_msg
```

Shell will then prompt you to enter a message, and then just type enter.


### Close the channel

You have the following two ways to close the channel.

1. Bilateral closing

```
ruby GPC.rb send_closing_request
```
Closing in this way closes the channel immediately and you just need to wait for a settlement transaction to be on chain.

2. Unilateral closing

```
ruby GPC.rb close_channel
```
The advantage of this method is that you don't need to interact with the other party. However, please note that you are committing a closing transaction instead of a settlement transaction, and the Monitor will commit the corresponding settlement transaction after a hundred blocks of the closing transaction on chain.