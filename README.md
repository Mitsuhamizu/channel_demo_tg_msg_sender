# channel_demo_tg_msg_sender

It's a tg bot service, which simply means you set up a payment channel with the server, and then exchange ckb for my [UDT](https://github.com/ZhichunLu-11/ckb-gpc-contract/blob/c8ad9ef42c6dd9e334c5099fa9510cef2997557d/main.c). Then you can have the tg bot pin the message you want to pin to the group. The idea of GPC is from [A Generic Payment Channel Construction and Its Composability](https://talk.nervos.org/t/a-generic-payment-channel-construction-and-its-composability/4697). 
Also, you can view the contract codes for [GPC](https://github.com/ZhichunLu-11/ckb-gpc-contract/blob/c8ad9ef42c6dd9e334c5099fa9510cef2997557d/main.c) and [UDT](https://github.com/ZhichunLu-11/ckb-gpc-contract/blob/c8ad9ef42c6dd9e334c5099fa9510cef2997557d/c/simple_UDT.c).

## Prerequisites

* [ckb testnet file](https://github.com/nervosnetwork/ckb).
* [ckb indexer file](https://github.com/nervosnetwork/ckb-indexer).

ckb testnet file means the folder where you run testnet, ckb indexer is the same. I suggest you make sure both are synced to the latest block. Then, you can stop both services on your machine.

## Usage

### Get docker

``` 
docker pull zhichunlu01/channel:latest
```

### Run docker

``` 
docker run -it -v <db folder>:/data/db -v <testnet folder>:/testnet -v <ckb indexer folder>:/indexer_tmp  --rm zhichunlu01/channel:latest
```

To run this docker you need to commit the paths to three folders, which stand for db, ckb testnet and ckb_indexer. In the first time, the db path should be an empty folder. Then, I give the example in my machine.

``` 
docker run -it -v /Users/ZhiChunLu/test_db/:/data/db -v /Users/ZhiChunLu/ckb/testnet/:/testnet -v /Users/ZhiChunLu/ckb/ckb-indexer/tmp/:/indexer_tmp  --rm zhichunlu01/channel:latest
```

If you are running docker for the first time, initialize the client and run the monitor first. Please don't forget to prefix your private key with 0x.

``` 
ruby GPC.rb init <Your private key>
nohup ruby GPC.rb monitor &
```

If you've initialized it before, then docker will load it for you on startup. So you can just use the client directly.

### Create channel

Then you can use the client to create a channel.

``` 
ruby GPC.rb send_establishment_request --funding <quantity>
```

For example, 

``` 
ruby GPC.rb send_establishment_request --funding ckb:200 UDT:0
```

Please follow the format of funding, even if the amount of UDT you want to put in is zero. Then, if the channel is established successfully, you should see 

``` 

channel is established, please wait the transaction on chain.
```

Please note that you cannot make payments at this time, you will need to wait for the funding transaction to be on-chain. You will know this information in the next command.

### List channel

``` 

ruby GPC.rb list_channel
```

This allows you to see the status of all your channels. For example, 

``` 

channel f119905665a0dea6a3eb6cbdc9bcf75b, with 4 payments and stage is 3
 local's ckb: 80 ckbytes, local's UDT 88.
 remote's ckb: 120 ckbytes, remote's UDT 1999912.
```

* `f119905665a0dea6a3eb6cbdc9bcf75b` is the channel id.
* `stage = 0` means the funding tx is not onchain, `stage = 1` means the funding tx is onchain. And now you can make payments. `stage > 1` means the channel is going to closing. So please not make any payment at that point.

### Exchange UDT

As you can see, you only put in CKB when you build the channel (If you've previously closed the channel while you held UDT, you can also invest UDTs). To make the process more fun, I made the bot only accept UDT as the only currency. So you first need to exchange for UDT. 10 CKBytes can exchange 1 UDT.

``` 
ruby GPC.rb make_exchange_ckb_to_udt --quantity 20
```

You can replace `20` with any number you want, as long as you have enough ckbytes. Also, you can trade UDT for CKB, just use make_exchange_udt_to_ckb. `quantity` is the amount of asset to be relaced, in this case 20 CKBytes, and if it is udt_to_ckb, then quantity is the UDTs.

Note, if you took some UDTs with you when you closed the channel before, then unfortunately they can't be replaced with CKBytes in the future because the server doesn't put in any CKBytes when it opens any channel.

### Inquiry msg id.

If you want to pin a msg already in this chat, you need to know the id of it firstly. 

``` 
ruby GPC.rb inquiry_msg --text <text>
```

For example

``` 
ruby GPC.rb inquiry_msg --text '123'
'123' sent by Zhichun in group_test at 2020-11-12T16:14:49+08:00, the id of this msg is 146.
Timed out. If you fail to receive the data, you should try again.
```

### Pin msg

After knowing the id, you can pin a msg with specific id. 

``` 
ruby GPC.rb pin_msg --id <msg_id> --duration <seconds> --price <price_per_seconds>
```

Duration denotes how long you want to pin this msg, price means the UDT per second you are willing to pay. Since the UDT amount can only be an integer, the total price you enter ends up being rounded upwards. For example, if you input duration with 10 seconds and 0.01 UDT per second. The amount you want to pay is 0.1, but I will round it upward. So the actually amount is 1. In this case, the server will treat your bid as 0.1 UDT per second.

If a message is currently pinned, then you must meet both of the following conditions to replace it.

* Your message will last longer than the rest of the current pinned message.
* Your price is higher than the current one.

You can use the following command to look up the remaining life and price of the current pinned message.

``` 
ruby GPC.rb inquiry_bid
```

If your pinned message is replaced before it runs out of life, then I will notify you in the tg group to initiate a refund. The refund is the amount of its remaining life multiplied by the price.

For example, the robot will send

``` 
0x470dcdc5e44064909650113a274b3b36aecb6dc7, please initiate a refund.
```
`0x470dcdc5e44064909650113a274b3b36aecb6dc7` is your pubkey.
Then, you can run 

``` 
ruby GPC.rb refund
```
to get your refund.

### Send and pin tg msg

Of course, you can let the bot pin msg with any content you want, which means you let the bot send a msg and pin it immediately.

``` 
ruby GPC.rb pin_msg --text <text> --duration <seconds> --price <price_per_seconds>
```

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

The advantage of this method is that you don't need to interact with the other party. However, please note that you are committing a closing transaction instead of a settlement transaction, and the Monitor will commit the corresponding settlement transaction after 100 blocks of the closing transaction on chain.

## FAQ

### This application clearly doesn't require a payment channel to implement, so why are you forcing the inclusion of a payment channel.

This is actually a demo of a payment channel, so I actually just forced it in because I couldn't find a better idea. If you think of a better way to use it, please let me know.

###  Why is it so un-robust? If I have a problem on the way to an interaction(Like disconnecting the Internet.), it doesn't even work!

You make a good point, it is indeed very un-robust and I apologize for that, at the moment I haven't done some implementation that adds the robustness function (retransmission mechanism etc). So when you find that it doesn't work, one of the best ways to close that channel is by unilaterally closing it and then reopening it later.
