# File management

Open an application's **Files** tab. The list/grid toggle is persisted as `view=grid` in the URL along with search, sort, tags and pagination. Lists show 25 files per page. Image cards use private generated thumbnails; other files have type placeholders. Click a filename for the details dialog: private preview when available, source dimensions, type, size, upload date, tags, processing state, original storage destination and download.

**Select page** selects only the visible page. Individual selection uses accessible checkbox buttons. Clear removes the selection. Changing filters, page, view or application clears selection. Background processing refreshes preserve the selection for files still visible. Switching applications also cancels queued uploads and clears upload results, preventing accidental storage in another application.

**Edit tags** adds, removes (case-insensitive) or replaces selected files' tags. Replace with an empty list clears tags. Existing validation applies to each resulting file (20 tags maximum). Tag read/modify/write operations share the file lock with storage lifecycle operations.

**Delete selected** requires confirmation and attempts physical removal. Bulk actions accept at most 25 unique canonical UUIDs, reauthorize the application and each file, and report partial success. Failed visible files stay selected and show safe error messages; physical cleanup failures keep quota accounting and durable recovery from the storage milestone. Files removed elsewhere may no longer remain selected.

**Copy private link** writes an absolute session download URL to the clipboard. It is **not a public share link**: the recipient must sign in and have access to that file. Clipboard failures offer the Download button as an alternative. Copying a URL does not create permissions or tokens.

Drag files onto the upload area or choose up to five files. Each entry shows progress and a remove/cancel action. Submit to store completed transfers. Each stored upload gets its own success/failure result. After failed storage, **Retry: reselect file** explains that you must choose/drop it again, because LiveView's consumed temporary bytes are gone. Oversized files and too many entries show validation errors. File size/quota/storage rules remain enforced on the server.

## Where to edit

- `lib/app_web/features/dashboard/dashboard_live.ex` and `.html.heex`: URL state, selection, dialogs and bulk/upload feedback.
- `lib/app_web/features/files/file_components.ex`: reusable file media and private-link controls.
- `lib/app/storage/file_management.ex`: bounded, application-scoped details and bulk service.
- `lib/app/storage.ex`: locked tag mutations and existing lifecycle services.
- `lib/app_web/components/ui/file_upload.ex`: shared drag/drop picker, progress and cancel.
- `assets/js/clipboard.mjs`: clipboard hook and honest success/failure feedback.

This milestone adds no dependencies or database migrations. Visual browser QA was unavailable in this environment; LiveView, service and JavaScript tests cover behavior and access boundaries. Expiring public sharing is a separate future milestone in the [active roadmap](../agent/01-replacement-plan.md).
