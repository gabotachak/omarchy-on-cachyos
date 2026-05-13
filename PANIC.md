# PANIC.md — System Recovery Guide

The system uses BTRFS with Snapper + snap-pac. Every `pacman` operation
automatically creates a pre/post snapshot pair. This file describes how to
roll back to a working state depending on how badly things are broken.

---

## Step 0 — Find the snapshot to restore

If you can get a terminal at all, list snapshots:

```bash
sudo snapper list
```

Look for the **pre** snapshot just before the update that broke things.
Note its number — you'll use it below.

---

## Case 1: System boots, but Hyprland / SDDM doesn't start

Switch to a TTY:

```
Ctrl + Alt + F2
```

Log in as `gabotachak`, then:

```bash
sudo snapper list                  # find the pre snapshot number
sudo snapper rollback <number>
sudo reboot
```

Limine will boot the rolled-back subvolume on the next start.

---

## Case 2: System doesn't boot at all (kernel panic, black screen, etc.)

Boot from a **CachyOS live USB**, open a terminal, then:

```bash
# Mount the BTRFS partition (adjust device if needed)
sudo mount /dev/nvme0n1p2 /mnt

# List all subvolumes — find the snapshot you want
# It will look like: ID 270 ... path @/.snapshots/3/snapshot
sudo btrfs subvolume list /mnt

# Set that snapshot as the default subvolume to boot into
sudo btrfs subvolume set-default <ID> /mnt

sudo umount /mnt
sudo reboot
```

On next boot, Limine loads the snapshot as if it were the normal system.
Once you're back in, run `sudo snapper rollback <n>` properly so Snapper
tracks it, then reboot once more.

---

## After recovery — clean up

Once back in a working system, confirm the rollback took effect and remove
stale snapshots if disk space is a concern:

```bash
sudo snapper list
sudo snapper delete <number>       # delete a specific snapshot
sudo snapper delete <n1>-<n2>      # delete a range
```

---

## Snapshot schedule (for reference)

| Type | Trigger | Retention |
|---|---|---|
| pre/post | Every `pacman` operation (snap-pac) | 20 pairs |
| hourly | snapper-timeline.timer | 5 |
| daily | snapper-timeline.timer | 7 |
| weekly | snapper-timeline.timer | 4 |
| monthly | snapper-timeline.timer | 3 |

Config lives at `/etc/snapper/configs/root`.
