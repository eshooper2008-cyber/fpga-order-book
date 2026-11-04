# FPGA Low-Latency Order Book (work in progress)

A hardware order book written in **Verilog**: it reads a stream of market-data messages (new orders, trades, cancels) and keeps track of the **best bid** and **best ask** for one stock, aiming for an update within a few clock cycles of each message arriving. This is the kind of system trading firms build on FPGAs, where every nanosecond counts.

The design is verified in simulation, with a self-checking testbench for every module.

> **Who wrote what:** I write all of the Verilog modules in `src/`. The testbenches in `tests/` were written by Claude (Anthropic's AI assistant), only to test my code.

---

## Progress

| Module | What it does | Status |
|---|---|---|
| `msg_rx` | Turns the incoming byte stream into message fields | ✅ **Done and tested** |
| `order_table` | Remembers every open order (side, price, shares) by order ID | ✅ **Done and tested** |
| `price_levels` | Total shares waiting at every price, for bids and asks | ⏳ Next |
| `best_price` | Finds the best bid and ask in one cycle (bitmap + priority encoder) | Planned |
| `tob_output` | Sends a top-of-book update whenever the best bid or ask changes | Planned |
| `top` | Connects everything and measures latency in clock cycles | Planned |

```
bytes ─► msg_rx ─► order_table ─► price_levels ─► best_price ─► tob_output ─► updates
```

---

## Message format

To start with, every message is a fixed **18 bytes**, modelled on NASDAQ's ITCH 5.0 feed. Numbers are big-endian, and prices have 4 implied decimals (`501000` = $50.1000). Real ITCH messages come later.

| Bytes | Field | Used by |
|---|---|---|
| 0 | Type: `A` add, `E` execute, `X` cancel, `D` delete, `U` replace | all |
| 1 – 4 | Order ID | all |
| 5 | Side: `B` buy / `S` sell | add |
| 6 – 9 | Shares | add, execute, cancel, replace |
| 10 – 13 | Price | add, replace |
| 14 – 17 | New order ID | replace |

---

## The message receiver (`src/msg_rx.v`)

Bytes arrive one per clock with a `valid` signal. A 5-bit counter tracks which byte of the message is arriving (0–17), and a `case` on the counter shifts each byte into its field: type, order ID, side, shares, price and new order ID. When byte 17 arrives, the counter resets and `msg_valid` goes high for exactly **one clock**, on the same edge that captures the last byte. The next module can use the message on the very next clock.

### Testing

[`tests/tb_msg_rx.v`](tests/tb_msg_rx.v) is a self-checking testbench (written by Claude to test my parser). It records every message it sends, compares each one the parser outputs field by field, and checks the timing of `msg_valid`.

| Test | Checks |
|---|---|
| Single add order | Every field decoded correctly |
| Every message type | Add, execute, cancel, replace and delete, back to back |
| Big-endian byte order | A different byte in every position, so offset or byte-order mistakes show up |
| Max and zero values | All-ones (`0xFFFFFFFF`) and all-zero fields |
| 200 random, back to back | One byte every clock, no gaps |
| 200 random, with gaps | Random idle cycles between bytes and between messages |
| Idle | Nothing fires while `valid` is low |

**Result: all tests pass, with 411 messages checked.**

```
PASS  single add order
PASS  every message type
PASS  big-endian byte order
PASS  max and zero values
PASS  200 random, back to back
PASS  200 random, with gaps
PASS  idle: no output while valid is low
--------------------------------------------
ALL TESTS PASSED  (411 messages checked)
```

### Run it yourself

- **In the browser (nothing to install):** paste `tests/tb_msg_rx.v` and `src/msg_rx.v` into [EDA Playground](https://www.edaplayground.com), choose **Icarus Verilog**, and click **Run**.
- **With Icarus Verilog:**
  ```bash
  iverilog -g2005 -o sim tests/tb_msg_rx.v src/msg_rx.v
  vvp sim
  ```

---

## The order table (`src/order_table.v`)

Execute, cancel, delete and replace messages only carry an order ID, not the side or price. To update the book, the hardware has to remember every open order. `order_table` stores each one in a 256-entry memory, using the low 8 bits of the order ID as the address:

```
 71        64 63                 32 31                  0
┌────────────┬─────────────────────┬─────────────────────┐
│ side (8)   │ price (32)          │ shares (32)         │   one entry, 72 bits
└────────────┴─────────────────────┴─────────────────────┘
```

An empty slot is all zeros. For each message it updates the entry and outputs one change for the next stage: *add or remove some shares, at this price, on this side*.

| Message | Table | Output |
|---|---|---|
| Add | write `{side, price, shares}` | +shares at price |
| Execute / Cancel | subtract the shares, clear the slot if none are left | −shares at the order's price |
| Delete | clear the slot | −all remaining shares |
| Replace | clear the old slot, write the new one (keeping the old side) | −old shares at old price, then **on the next clock** +new shares at new price |
| Any of these on an unknown ID | nothing | `not_found` |

A replace changes two price levels, but there is only one set of outputs, so the add is saved in `pending_data` and sent one clock later. Messages are at least 18 clocks apart, so that clock is always free.

Every output appears one clock after the message.

### Testing

[`tests/tb_order_table.v`](tests/tb_order_table.v) (written by Claude to test my module) keeps its own copy of the order table. For every message it works out which change(s) should come out, checks each output, and compares the module's memory with its copy slot by slot.

| Test | Checks |
|---|---|
| Add buy and sell | Side decoded correctly, change goes out |
| Execute partial then full | Shares go down, slot is cleared at 0, then `not_found` |
| Cancel partial then full | Same for cancels |
| Delete | All remaining shares removed, slot cleared |
| Replace keeps side, two outputs | Removal then add on the next clock; new ID works, old ID is gone |
| Replace into same ID | New order overwrites the old one correctly |
| Unknown order | Execute, cancel, delete and replace all give `not_found` |
| Max values | All-ones shares and price |
| Idle and unknown types | Nothing happens |
| 3000 random messages | Random mix of all five types, with random gaps, against the model |

**Result: all tests pass, with 3027 messages and 3481 outputs checked.** Three bugs from earlier versions were also put back one at a time (wrong fully-filled check, replace using the message's side, replace sent as an add) to make sure the testbench catches each one.

```
PASS  add buy and sell
PASS  execute partial then full
PASS  cancel partial then full
PASS  delete
PASS  replace keeps side, two outputs
PASS  replace into same ID
PASS  unknown order -> not_found
PASS  max values
PASS  idle and unknown types: no output
PASS  3000 random messages vs model
--------------------------------------------
ALL TESTS PASSED  (3027 messages, 3481 outputs checked)
```

### Run it yourself

```bash
iverilog -g2005 -o sim tests/tb_order_table.v src/order_table.v
vvp sim
```

Or paste both files into EDA Playground as above.

**Current limits:** only 256 orders at once (IDs that share their low 8 bits would collide), and the memory is read in the same clock it's written, so it won't map onto block RAM yet. A hash of the order ID and a read-then-write pipeline come later.

---

## Next steps

1. **`price_levels`:** total shares at every price for bids and asks.
2. Build the one-cycle best bid/ask finder.
3. Measure latency in clock cycles, then synthesize to get resource use and maximum clock speed.
4. Later: support real NASDAQ ITCH 5.0 messages, and start processing a message before it has fully arrived (cut-through) to cut latency.
