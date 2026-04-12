enum PostKind {
  helpOffer,
  helpRequest,
  /// Community gathering; stored in the `posts` collection with event fields.
  communityEvent,
}

String postKindToFirestore(PostKind k) {
  switch (k) {
    case PostKind.helpOffer:
      return 'help_offer';
    case PostKind.helpRequest:
      return 'help_request';
    case PostKind.communityEvent:
      return 'community_event';
  }
}

PostKind? postKindFromFirestore(String? v) {
  switch (v) {
    case 'help_offer':
      return PostKind.helpOffer;
    case 'help_request':
      return PostKind.helpRequest;
    case 'community_event':
      return PostKind.communityEvent;
    default:
      return null;
  }
}
