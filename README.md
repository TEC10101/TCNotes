# ReminderNotes

A lightweight in-game note manager for World of Warcraft Wrath v3.3.5, providing global and character-scoped notes, inline editing, and simple reminders.

<img width="517" height="603" alt="image" src="https://github.com/user-attachments/assets/19b81213-2879-4c48-9ca6-d4e3f55c54f5" />

Features

- **Global & Character Notes:** Keep notes that apply to all characters or specific to the current character.
- **Inline Editing:** Click a note to edit inline; press Enter to save or Escape to cancel (and clear the edit field).
- **Add Notes Quickly:** Type in the section "add" box and press Enter to add a note.
- **Reminders:** Per-note reminder types: `Next Login`, `Every Login`, or `At Level <n>`; reminders show a popup when triggered.
- **Link Insertion:** Shift-click item/spell links to insert them into the focused note edit box.
- **Soft Delete & Undo:** Deleting a note flags it for removal and pushes it to an undo stack; use the undo command to restore.
- **UI:** Resizable, draggable frame with a lock button to prevent moving/closing.

<img width="479" height="224" alt="image" src="https://github.com/user-attachments/assets/bb70bdd2-2faf-48a2-88ad-5c8ea31fe19a" />

How To (In-Game)

- **Toggle UI:** `/notes` — Toggle the ReminderNotes window.
- **Undo last delete:** `/notes undo` — Restore the most recently soft-deleted note (if available).
- **Prune deleted notes:** `/notes prune` — Permanently remove notes flagged as deleted from the SavedVariables.
- **Debug (developer):** `/notes debug` — (internal) runs initialization/debug code.

UI Interactions

- Click a visible note (left-click) to enter inline edit mode.
- In inline edit: press `Enter` to save changes, `Escape` to cancel and clear the edit text.
- In the section add box: type a note and press `Enter` to add; press `Escape` to clear and remove focus.
- Use the small `R`/`!` button on each row to open the reminder dialog and choose a reminder type.
- Delete (row close button) will soft-delete a note (you can undo with `/notes undo`).
- Drag the "Notes" header to move the frame; use the lock button to lock/unlock movement.

Installation / Reload

- Place the `ReminderNotes` folder in your `Interface/AddOns` directory and launch WoW.
- While in-game, run `/reload` after adding/updating the addon to load changes.

License

- **GNU General Public License v3.0:** This addon is licensed under the
- GNU GPL v3.0. See the bundled `LICENSE` file for the full license text.

If you redistribute or modify this addon, ensure you comply with the
terms of the GPL v3.0 (preserve notices, provide source, include the
license, etc.).
