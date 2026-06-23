// lib/models/files_models.dart
//
// Models for the Files browser and the Signature signing flow.
// Keep these separate from models.dart so the chat models stay focused.

class RemoteFile {
  final String id;
  final String name;
  final String url;
  final int size;
  final String sizeDisplay;
  final String extension;
  final bool isImage;
  final bool isPdf;
  final String typeCategory;
  final String folderName;
  final String uploadedBy;
  final String createdAt;

  RemoteFile({
    required this.id,
    required this.name,
    required this.url,
    required this.size,
    required this.sizeDisplay,
    required this.extension,
    required this.isImage,
    required this.isPdf,
    required this.typeCategory,
    required this.folderName,
    required this.uploadedBy,
    required this.createdAt,
  });

  factory RemoteFile.fromJson(Map<String, dynamic> j) => RemoteFile(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        url: '${j['url'] ?? ''}',
        size: (j['size'] ?? 0) is int ? j['size'] ?? 0 : int.tryParse('${j['size']}') ?? 0,
        sizeDisplay: '${j['size_display'] ?? ''}',
        extension: '${j['extension'] ?? ''}',
        isImage: j['is_image'] == true,
        isPdf: j['is_pdf'] == true,
        typeCategory: '${j['type_category'] ?? 'other'}',
        folderName: '${j['folder_name'] ?? ''}',
        uploadedBy: '${j['uploaded_by'] ?? ''}',
        createdAt: '${j['created_at'] ?? ''}',
      );
}

/// A signature request where the current user is a signer.
class SignRequest {
  final String requestId;
  final String signerToken;
  final String title;
  final String message;
  final String documentName;
  final String status;        // request status
  final String signerStatus;  // this signer's status
  final bool orderedSigning;
  final int myOrder;
  final String createdBy;
  final String createdAt;
  final String? expiresAt;
  final String previewUrl;
  final String downloadUrl;

  SignRequest({
    required this.requestId,
    required this.signerToken,
    required this.title,
    required this.message,
    required this.documentName,
    required this.status,
    required this.signerStatus,
    required this.orderedSigning,
    required this.myOrder,
    required this.createdBy,
    required this.createdAt,
    required this.expiresAt,
    required this.previewUrl,
    required this.downloadUrl,
  });

  factory SignRequest.fromJson(Map<String, dynamic> j) => SignRequest(
        requestId: '${j['request_id'] ?? ''}',
        signerToken: '${j['signer_token'] ?? ''}',
        title: '${j['title'] ?? ''}',
        message: '${j['message'] ?? ''}',
        documentName: '${j['document_name'] ?? ''}',
        status: '${j['status'] ?? ''}',
        signerStatus: '${j['signer_status'] ?? ''}',
        orderedSigning: j['ordered_signing'] == true,
        myOrder: (j['my_order'] ?? 1) is int ? j['my_order'] ?? 1 : 1,
        createdBy: '${j['created_by'] ?? ''}',
        createdAt: '${j['created_at'] ?? ''}',
        expiresAt: j['expires_at'] == null ? null : '${j['expires_at']}',
        previewUrl: '${j['preview_url'] ?? ''}',
        downloadUrl: '${j['download_url'] ?? ''}',
      );
}

/// A positioned field the signer must complete.
class SignField {
  final String id;
  final String type;   // signature | initials | date | text
  final int page;
  final double x, y, w, h; // percentages 0-100
  final String label;
  final bool required;
  final bool filled;

  SignField({
    required this.id,
    required this.type,
    required this.page,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.label,
    required this.required,
    required this.filled,
  });

  factory SignField.fromJson(Map<String, dynamic> j) => SignField(
        id: '${j['id'] ?? ''}',
        type: '${j['type'] ?? 'signature'}',
        page: (j['page'] ?? 1) is int ? j['page'] ?? 1 : 1,
        x: (j['x'] ?? 0).toDouble(),
        y: (j['y'] ?? 0).toDouble(),
        w: (j['w'] ?? 0).toDouble(),
        h: (j['h'] ?? 0).toDouble(),
        label: '${j['label'] ?? ''}',
        required: j['required'] == true,
        filled: j['filled'] == true,
      );
}

/// A reusable saved signature.
class SavedSig {
  final String id;
  final String name;
  final String sigType; // draw | type | upload
  final bool isDefault;
  final String data;    // typed text OR base64 data URI

  SavedSig({
    required this.id,
    required this.name,
    required this.sigType,
    required this.isDefault,
    required this.data,
  });

  factory SavedSig.fromJson(Map<String, dynamic> j) => SavedSig(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        sigType: '${j['sig_type'] ?? 'draw'}',
        isDefault: j['is_default'] == true,
        data: '${j['data'] ?? ''}',
      );
}

class SignDetail {
  final SignRequest request;
  final bool blockedByOrder;
  final List<SignField> fields;
  final List<SavedSig> savedSignatures;

  SignDetail({
    required this.request,
    required this.blockedByOrder,
    required this.fields,
    required this.savedSignatures,
  });

  factory SignDetail.fromJson(Map<String, dynamic> j) => SignDetail(
        request: SignRequest.fromJson(j['request'] ?? {}),
        blockedByOrder: j['blocked_by_order'] == true,
        fields: ((j['fields'] ?? []) as List)
            .map((e) => SignField.fromJson(e))
            .toList(),
        savedSignatures: ((j['saved_signatures'] ?? []) as List)
            .map((e) => SavedSig.fromJson(e))
            .toList(),
      );
}
