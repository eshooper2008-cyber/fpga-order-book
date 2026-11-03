# FPGA Low-Latency Order Book (work in progress)

A hardware order book written in **Verilog**: it reads a stream of market-data messages (new orders, trades, cancels) and keeps track of the **best bid** and **best ask** for one stock, aiming for an update within a few clock cycles of each message arriving. This is the kind of system trading firms build on FPGAs, where every nanosecond counts.

The design is verified in simulation, with a self-checking testbench for every module.

---

## Progress

| Module | What it does | Status |
|---|---|---|
| `msg_rx` | Turns the incoming byte stream into message fields | ✅ **Done and tested** |
| `order_table` | Remembers every open order (side, price, shares) by order ID | ⏳ Next |
| `book_update` | Turns each message into a change at one price level | Planned |
| `price_levels` | Total shares waiting at every price, for bids and asks | Planned |
| `best_price` | Finds the best bid and ask in one cycle (bitmap + priority encoder) | Planned |
| `tob_output` | Sends a top-of-book update whenever the best bid or ask changes | Planned |
| `top` | Connects everything and measures latency in clock cycles | Planned |

```
bytes ─► msg_rx ─► order_table ─► book_update ─► price_levels ─► best_price ─► tob_output ─► updates
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

[`tests/tb_msg_rx.v`](tests/tb_msg_rx.v) is a self-checking testbench. It records every message it sends, compares each one the parser outputs field by field, and checks the timing of `msg_valid`.

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

## Next steps

1. **`order_table`:** store orders in block RAM so execute, cancel, delete and replace messages can find their order's side and price.
2. Build the price levels and the one-cycle best bid/ask finder.
3. Measure latency in clock cycles, then synthesize to get resource use and maximum clock speed.
4. Later: support real NASDAQ ITCH 5.0 messages, and start processing a message before it has fully arrived (cut-through) to cut latency.
