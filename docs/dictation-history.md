# Local dictation history

Completed nonempty work dictation is written once to the existing application support folder's Dictations directory, independently of automatic paste. Each private0600 JSON file is atomically renamed into place; no extra microphone recording is retained.

Version1 record: schemaVersion1, UUID id (also the filename stem), timestamp in Unix seconds, language BCP47 string, text. Failed or cancelled recognition does not create a record. Saving failure does not block paste and appears in the existing dictation panel. The last saved text is restored after restart.

AWhisper reads these files without modifying either application's history. It labels Cicada rows, merges by time, and offers text copy; existing meeting records are unchanged.
