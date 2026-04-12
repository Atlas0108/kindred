enum PostKind {
  helpOffer,
  helpRequest,
  thankYou,
}

String postKindToFirestore(PostKind k) {
  switch (k) {
    case PostKind.helpOffer:
      return 'help_offer';
    case PostKind.helpRequest:
      return 'help_request';
    case PostKind.thankYou:
      return 'thank_you';
  }
}

PostKind? postKindFromFirestore(String? v) {
  switch (v) {
    case 'help_offer':
      return PostKind.helpOffer;
    case 'help_request':
      return PostKind.helpRequest;
    case 'thank_you':
      return PostKind.thankYou;
    default:
      return null;
  }
}
