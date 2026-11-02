import CoreData
import SwiftUI
import YafoKit

/// Kommentare am Termin als Chat-Verlauf: eigene rechts, andere links mit Avatar und Name.
/// Eigene Kommentare lassen sich per Kontextmenü bearbeiten und löschen.
struct CommentsSection: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var event: Event
    let me: Member?

    @FetchRequest private var comments: FetchedResults<Comment>
    @State private var draft = ""
    @State private var editing: Comment?
    @State private var editText = ""
    @FocusState private var inputFocused: Bool

    init(event: Event, me: Member?) {
        self.event = event
        self.me = me
        _comments = FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt)],
                                 predicate: NSPredicate(format: "event == %@", event))
    }

    var body: some View {
        Section("Comments") {
            if comments.isEmpty {
                Text("No comments yet")
                    .foregroundStyle(.secondary)
            }
            ForEach(comments) { comment in
                CommentBubble(comment: comment, isMine: comment.author != nil && comment.author == me)
                    .listRowSeparator(.hidden)
                    .contextMenu {
                        if comment.author != nil && comment.author == me {
                            Button("Edit", systemImage: "pencil") {
                                editText = comment.text ?? ""
                                editing = comment
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                model.repository.delete(comment)
                                model.save()
                            }
                        }
                    }
            }
            if me != nil {
                HStack(alignment: .bottom) {
                    TextField("Write a comment", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($inputFocused)
                    Button("Send", systemImage: "arrow.up.circle.fill", action: send)
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .alert("Edit Comment", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Comment", text: $editText)
            Button("Save") {
                if let editing {
                    model.repository.edit(editing, text: editText)
                    model.save()
                }
                editing = nil
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.repository.addComment(text, to: event, author: me)
        model.save()
        draft = ""
    }
}

private struct CommentBubble: View {
    @ObservedObject var comment: Comment
    let isMine: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMine {
                Spacer(minLength: 40)
            } else if let author = comment.author {
                MemberAvatar(member: author, size: 28)
            }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                if !isMine {
                    Text(comment.author?.displayLabel ?? String(localized: "Unknown"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(comment.text ?? "")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(isMine ? Color.white : Color.primary)
                    .background(RoundedRectangle(cornerRadius: 16)
                        .fill(isMine ? Color.accentColor : Color.secondary.opacity(0.15)))
                HStack(spacing: 4) {
                    if let date = comment.createdAt {
                        Text(date.formatted(.relative(presentation: .named)))
                    }
                    if comment.editedAt != nil {
                        Text("· edited")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            if !isMine {
                Spacer(minLength: 40)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
