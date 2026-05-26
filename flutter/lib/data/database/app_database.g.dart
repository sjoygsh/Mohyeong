// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class Mangas extends Table with TableInfo<Mangas, Manga> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Mangas(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      '_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL PRIMARY KEY');
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  late final GeneratedColumn<int> source = GeneratedColumn<int>(
      'source', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
      'url', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
      'artist', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
      'author', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  static const VerificationMeta _genreMeta = const VerificationMeta('genre');
  late final GeneratedColumn<String> genre = GeneratedColumn<String>(
      'genre', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
      'status', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _thumbnailUrlMeta =
      const VerificationMeta('thumbnailUrl');
  late final GeneratedColumn<String> thumbnailUrl = GeneratedColumn<String>(
      'thumbnail_url', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  static const VerificationMeta _favoriteMeta =
      const VerificationMeta('favorite');
  late final GeneratedColumn<int> favorite = GeneratedColumn<int>(
      'favorite', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _lastUpdateMeta =
      const VerificationMeta('lastUpdate');
  late final GeneratedColumn<int> lastUpdate = GeneratedColumn<int>(
      'last_update', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: '');
  static const VerificationMeta _nextUpdateMeta =
      const VerificationMeta('nextUpdate');
  late final GeneratedColumn<int> nextUpdate = GeneratedColumn<int>(
      'next_update', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: '');
  static const VerificationMeta _initializedMeta =
      const VerificationMeta('initialized');
  late final GeneratedColumn<int> initialized = GeneratedColumn<int>(
      'initialized', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _viewerMeta = const VerificationMeta('viewer');
  late final GeneratedColumn<int> viewer = GeneratedColumn<int>(
      'viewer', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _chapterFlagsMeta =
      const VerificationMeta('chapterFlags');
  late final GeneratedColumn<int> chapterFlags = GeneratedColumn<int>(
      'chapter_flags', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _coverLastModifiedMeta =
      const VerificationMeta('coverLastModified');
  late final GeneratedColumn<int> coverLastModified = GeneratedColumn<int>(
      'cover_last_modified', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _dateAddedMeta =
      const VerificationMeta('dateAdded');
  late final GeneratedColumn<int> dateAdded = GeneratedColumn<int>(
      'date_added', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _updateStrategyMeta =
      const VerificationMeta('updateStrategy');
  late final GeneratedColumn<int> updateStrategy = GeneratedColumn<int>(
      'update_strategy', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT 0',
      defaultValue: const CustomExpression('0'));
  static const VerificationMeta _calculateIntervalMeta =
      const VerificationMeta('calculateInterval');
  late final GeneratedColumn<int> calculateInterval = GeneratedColumn<int>(
      'calculate_interval', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: 'DEFAULT 0 NOT NULL',
      defaultValue: const CustomExpression('0'));
  static const VerificationMeta _lastModifiedAtMeta =
      const VerificationMeta('lastModifiedAt');
  late final GeneratedColumn<int> lastModifiedAt = GeneratedColumn<int>(
      'last_modified_at', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT 0',
      defaultValue: const CustomExpression('0'));
  static const VerificationMeta _favoriteModifiedAtMeta =
      const VerificationMeta('favoriteModifiedAt');
  late final GeneratedColumn<int> favoriteModifiedAt = GeneratedColumn<int>(
      'favorite_modified_at', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: '');
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
      'version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT 0',
      defaultValue: const CustomExpression('0'));
  static const VerificationMeta _isSyncingMeta =
      const VerificationMeta('isSyncing');
  late final GeneratedColumn<int> isSyncing = GeneratedColumn<int>(
      'is_syncing', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT 0',
      defaultValue: const CustomExpression('0'));
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
      'notes', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT \'\'',
      defaultValue: const CustomExpression('\'\''));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        source,
        url,
        artist,
        author,
        description,
        genre,
        title,
        status,
        thumbnailUrl,
        favorite,
        lastUpdate,
        nextUpdate,
        initialized,
        viewer,
        chapterFlags,
        coverLastModified,
        dateAdded,
        updateStrategy,
        calculateInterval,
        lastModifiedAt,
        favoriteModifiedAt,
        version,
        isSyncing,
        notes
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mangas';
  @override
  VerificationContext validateIntegrity(Insertable<Manga> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('_id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['_id']!, _idMeta));
    }
    if (data.containsKey('source')) {
      context.handle(_sourceMeta,
          source.isAcceptableOrUnknown(data['source']!, _sourceMeta));
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
          _urlMeta, url.isAcceptableOrUnknown(data['url']!, _urlMeta));
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('artist')) {
      context.handle(_artistMeta,
          artist.isAcceptableOrUnknown(data['artist']!, _artistMeta));
    }
    if (data.containsKey('author')) {
      context.handle(_authorMeta,
          author.isAcceptableOrUnknown(data['author']!, _authorMeta));
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('genre')) {
      context.handle(
          _genreMeta, genre.isAcceptableOrUnknown(data['genre']!, _genreMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('thumbnail_url')) {
      context.handle(
          _thumbnailUrlMeta,
          thumbnailUrl.isAcceptableOrUnknown(
              data['thumbnail_url']!, _thumbnailUrlMeta));
    }
    if (data.containsKey('favorite')) {
      context.handle(_favoriteMeta,
          favorite.isAcceptableOrUnknown(data['favorite']!, _favoriteMeta));
    } else if (isInserting) {
      context.missing(_favoriteMeta);
    }
    if (data.containsKey('last_update')) {
      context.handle(
          _lastUpdateMeta,
          lastUpdate.isAcceptableOrUnknown(
              data['last_update']!, _lastUpdateMeta));
    }
    if (data.containsKey('next_update')) {
      context.handle(
          _nextUpdateMeta,
          nextUpdate.isAcceptableOrUnknown(
              data['next_update']!, _nextUpdateMeta));
    }
    if (data.containsKey('initialized')) {
      context.handle(
          _initializedMeta,
          initialized.isAcceptableOrUnknown(
              data['initialized']!, _initializedMeta));
    } else if (isInserting) {
      context.missing(_initializedMeta);
    }
    if (data.containsKey('viewer')) {
      context.handle(_viewerMeta,
          viewer.isAcceptableOrUnknown(data['viewer']!, _viewerMeta));
    } else if (isInserting) {
      context.missing(_viewerMeta);
    }
    if (data.containsKey('chapter_flags')) {
      context.handle(
          _chapterFlagsMeta,
          chapterFlags.isAcceptableOrUnknown(
              data['chapter_flags']!, _chapterFlagsMeta));
    } else if (isInserting) {
      context.missing(_chapterFlagsMeta);
    }
    if (data.containsKey('cover_last_modified')) {
      context.handle(
          _coverLastModifiedMeta,
          coverLastModified.isAcceptableOrUnknown(
              data['cover_last_modified']!, _coverLastModifiedMeta));
    } else if (isInserting) {
      context.missing(_coverLastModifiedMeta);
    }
    if (data.containsKey('date_added')) {
      context.handle(_dateAddedMeta,
          dateAdded.isAcceptableOrUnknown(data['date_added']!, _dateAddedMeta));
    } else if (isInserting) {
      context.missing(_dateAddedMeta);
    }
    if (data.containsKey('update_strategy')) {
      context.handle(
          _updateStrategyMeta,
          updateStrategy.isAcceptableOrUnknown(
              data['update_strategy']!, _updateStrategyMeta));
    }
    if (data.containsKey('calculate_interval')) {
      context.handle(
          _calculateIntervalMeta,
          calculateInterval.isAcceptableOrUnknown(
              data['calculate_interval']!, _calculateIntervalMeta));
    }
    if (data.containsKey('last_modified_at')) {
      context.handle(
          _lastModifiedAtMeta,
          lastModifiedAt.isAcceptableOrUnknown(
              data['last_modified_at']!, _lastModifiedAtMeta));
    }
    if (data.containsKey('favorite_modified_at')) {
      context.handle(
          _favoriteModifiedAtMeta,
          favoriteModifiedAt.isAcceptableOrUnknown(
              data['favorite_modified_at']!, _favoriteModifiedAtMeta));
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    }
    if (data.containsKey('is_syncing')) {
      context.handle(_isSyncingMeta,
          isSyncing.isAcceptableOrUnknown(data['is_syncing']!, _isSyncingMeta));
    }
    if (data.containsKey('notes')) {
      context.handle(
          _notesMeta, notes.isAcceptableOrUnknown(data['notes']!, _notesMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Manga map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Manga(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}_id'])!,
      source: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}source'])!,
      url: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}url'])!,
      artist: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}artist']),
      author: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}author']),
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      genre: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}genre']),
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}status'])!,
      thumbnailUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}thumbnail_url']),
      favorite: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}favorite'])!,
      lastUpdate: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_update']),
      nextUpdate: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}next_update']),
      initialized: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}initialized'])!,
      viewer: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}viewer'])!,
      chapterFlags: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}chapter_flags'])!,
      coverLastModified: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}cover_last_modified'])!,
      dateAdded: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}date_added'])!,
      updateStrategy: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}update_strategy'])!,
      calculateInterval: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}calculate_interval'])!,
      lastModifiedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_modified_at'])!,
      favoriteModifiedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}favorite_modified_at']),
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      isSyncing: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}is_syncing'])!,
      notes: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notes'])!,
    );
  }

  @override
  Mangas createAlias(String alias) {
    return Mangas(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class Manga extends DataClass implements Insertable<Manga> {
  final int id;
  final int source;
  final String url;
  final String? artist;
  final String? author;
  final String? description;
  final String? genre;
  final String title;
  final int status;
  final String? thumbnailUrl;
  final int favorite;
  final int? lastUpdate;
  final int? nextUpdate;
  final int initialized;
  final int viewer;
  final int chapterFlags;
  final int coverLastModified;
  final int dateAdded;
  final int updateStrategy;
  final int calculateInterval;
  final int lastModifiedAt;
  final int? favoriteModifiedAt;
  final int version;
  final int isSyncing;
  final String notes;
  const Manga(
      {required this.id,
      required this.source,
      required this.url,
      this.artist,
      this.author,
      this.description,
      this.genre,
      required this.title,
      required this.status,
      this.thumbnailUrl,
      required this.favorite,
      this.lastUpdate,
      this.nextUpdate,
      required this.initialized,
      required this.viewer,
      required this.chapterFlags,
      required this.coverLastModified,
      required this.dateAdded,
      required this.updateStrategy,
      required this.calculateInterval,
      required this.lastModifiedAt,
      this.favoriteModifiedAt,
      required this.version,
      required this.isSyncing,
      required this.notes});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['_id'] = Variable<int>(id);
    map['source'] = Variable<int>(source);
    map['url'] = Variable<String>(url);
    if (!nullToAbsent || artist != null) {
      map['artist'] = Variable<String>(artist);
    }
    if (!nullToAbsent || author != null) {
      map['author'] = Variable<String>(author);
    }
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || genre != null) {
      map['genre'] = Variable<String>(genre);
    }
    map['title'] = Variable<String>(title);
    map['status'] = Variable<int>(status);
    if (!nullToAbsent || thumbnailUrl != null) {
      map['thumbnail_url'] = Variable<String>(thumbnailUrl);
    }
    map['favorite'] = Variable<int>(favorite);
    if (!nullToAbsent || lastUpdate != null) {
      map['last_update'] = Variable<int>(lastUpdate);
    }
    if (!nullToAbsent || nextUpdate != null) {
      map['next_update'] = Variable<int>(nextUpdate);
    }
    map['initialized'] = Variable<int>(initialized);
    map['viewer'] = Variable<int>(viewer);
    map['chapter_flags'] = Variable<int>(chapterFlags);
    map['cover_last_modified'] = Variable<int>(coverLastModified);
    map['date_added'] = Variable<int>(dateAdded);
    map['update_strategy'] = Variable<int>(updateStrategy);
    map['calculate_interval'] = Variable<int>(calculateInterval);
    map['last_modified_at'] = Variable<int>(lastModifiedAt);
    if (!nullToAbsent || favoriteModifiedAt != null) {
      map['favorite_modified_at'] = Variable<int>(favoriteModifiedAt);
    }
    map['version'] = Variable<int>(version);
    map['is_syncing'] = Variable<int>(isSyncing);
    map['notes'] = Variable<String>(notes);
    return map;
  }

  MangasCompanion toCompanion(bool nullToAbsent) {
    return MangasCompanion(
      id: Value(id),
      source: Value(source),
      url: Value(url),
      artist:
          artist == null && nullToAbsent ? const Value.absent() : Value(artist),
      author:
          author == null && nullToAbsent ? const Value.absent() : Value(author),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      genre:
          genre == null && nullToAbsent ? const Value.absent() : Value(genre),
      title: Value(title),
      status: Value(status),
      thumbnailUrl: thumbnailUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailUrl),
      favorite: Value(favorite),
      lastUpdate: lastUpdate == null && nullToAbsent
          ? const Value.absent()
          : Value(lastUpdate),
      nextUpdate: nextUpdate == null && nullToAbsent
          ? const Value.absent()
          : Value(nextUpdate),
      initialized: Value(initialized),
      viewer: Value(viewer),
      chapterFlags: Value(chapterFlags),
      coverLastModified: Value(coverLastModified),
      dateAdded: Value(dateAdded),
      updateStrategy: Value(updateStrategy),
      calculateInterval: Value(calculateInterval),
      lastModifiedAt: Value(lastModifiedAt),
      favoriteModifiedAt: favoriteModifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(favoriteModifiedAt),
      version: Value(version),
      isSyncing: Value(isSyncing),
      notes: Value(notes),
    );
  }

  factory Manga.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Manga(
      id: serializer.fromJson<int>(json['_id']),
      source: serializer.fromJson<int>(json['source']),
      url: serializer.fromJson<String>(json['url']),
      artist: serializer.fromJson<String?>(json['artist']),
      author: serializer.fromJson<String?>(json['author']),
      description: serializer.fromJson<String?>(json['description']),
      genre: serializer.fromJson<String?>(json['genre']),
      title: serializer.fromJson<String>(json['title']),
      status: serializer.fromJson<int>(json['status']),
      thumbnailUrl: serializer.fromJson<String?>(json['thumbnail_url']),
      favorite: serializer.fromJson<int>(json['favorite']),
      lastUpdate: serializer.fromJson<int?>(json['last_update']),
      nextUpdate: serializer.fromJson<int?>(json['next_update']),
      initialized: serializer.fromJson<int>(json['initialized']),
      viewer: serializer.fromJson<int>(json['viewer']),
      chapterFlags: serializer.fromJson<int>(json['chapter_flags']),
      coverLastModified: serializer.fromJson<int>(json['cover_last_modified']),
      dateAdded: serializer.fromJson<int>(json['date_added']),
      updateStrategy: serializer.fromJson<int>(json['update_strategy']),
      calculateInterval: serializer.fromJson<int>(json['calculate_interval']),
      lastModifiedAt: serializer.fromJson<int>(json['last_modified_at']),
      favoriteModifiedAt:
          serializer.fromJson<int?>(json['favorite_modified_at']),
      version: serializer.fromJson<int>(json['version']),
      isSyncing: serializer.fromJson<int>(json['is_syncing']),
      notes: serializer.fromJson<String>(json['notes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      '_id': serializer.toJson<int>(id),
      'source': serializer.toJson<int>(source),
      'url': serializer.toJson<String>(url),
      'artist': serializer.toJson<String?>(artist),
      'author': serializer.toJson<String?>(author),
      'description': serializer.toJson<String?>(description),
      'genre': serializer.toJson<String?>(genre),
      'title': serializer.toJson<String>(title),
      'status': serializer.toJson<int>(status),
      'thumbnail_url': serializer.toJson<String?>(thumbnailUrl),
      'favorite': serializer.toJson<int>(favorite),
      'last_update': serializer.toJson<int?>(lastUpdate),
      'next_update': serializer.toJson<int?>(nextUpdate),
      'initialized': serializer.toJson<int>(initialized),
      'viewer': serializer.toJson<int>(viewer),
      'chapter_flags': serializer.toJson<int>(chapterFlags),
      'cover_last_modified': serializer.toJson<int>(coverLastModified),
      'date_added': serializer.toJson<int>(dateAdded),
      'update_strategy': serializer.toJson<int>(updateStrategy),
      'calculate_interval': serializer.toJson<int>(calculateInterval),
      'last_modified_at': serializer.toJson<int>(lastModifiedAt),
      'favorite_modified_at': serializer.toJson<int?>(favoriteModifiedAt),
      'version': serializer.toJson<int>(version),
      'is_syncing': serializer.toJson<int>(isSyncing),
      'notes': serializer.toJson<String>(notes),
    };
  }

  Manga copyWith(
          {int? id,
          int? source,
          String? url,
          Value<String?> artist = const Value.absent(),
          Value<String?> author = const Value.absent(),
          Value<String?> description = const Value.absent(),
          Value<String?> genre = const Value.absent(),
          String? title,
          int? status,
          Value<String?> thumbnailUrl = const Value.absent(),
          int? favorite,
          Value<int?> lastUpdate = const Value.absent(),
          Value<int?> nextUpdate = const Value.absent(),
          int? initialized,
          int? viewer,
          int? chapterFlags,
          int? coverLastModified,
          int? dateAdded,
          int? updateStrategy,
          int? calculateInterval,
          int? lastModifiedAt,
          Value<int?> favoriteModifiedAt = const Value.absent(),
          int? version,
          int? isSyncing,
          String? notes}) =>
      Manga(
        id: id ?? this.id,
        source: source ?? this.source,
        url: url ?? this.url,
        artist: artist.present ? artist.value : this.artist,
        author: author.present ? author.value : this.author,
        description: description.present ? description.value : this.description,
        genre: genre.present ? genre.value : this.genre,
        title: title ?? this.title,
        status: status ?? this.status,
        thumbnailUrl:
            thumbnailUrl.present ? thumbnailUrl.value : this.thumbnailUrl,
        favorite: favorite ?? this.favorite,
        lastUpdate: lastUpdate.present ? lastUpdate.value : this.lastUpdate,
        nextUpdate: nextUpdate.present ? nextUpdate.value : this.nextUpdate,
        initialized: initialized ?? this.initialized,
        viewer: viewer ?? this.viewer,
        chapterFlags: chapterFlags ?? this.chapterFlags,
        coverLastModified: coverLastModified ?? this.coverLastModified,
        dateAdded: dateAdded ?? this.dateAdded,
        updateStrategy: updateStrategy ?? this.updateStrategy,
        calculateInterval: calculateInterval ?? this.calculateInterval,
        lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
        favoriteModifiedAt: favoriteModifiedAt.present
            ? favoriteModifiedAt.value
            : this.favoriteModifiedAt,
        version: version ?? this.version,
        isSyncing: isSyncing ?? this.isSyncing,
        notes: notes ?? this.notes,
      );
  Manga copyWithCompanion(MangasCompanion data) {
    return Manga(
      id: data.id.present ? data.id.value : this.id,
      source: data.source.present ? data.source.value : this.source,
      url: data.url.present ? data.url.value : this.url,
      artist: data.artist.present ? data.artist.value : this.artist,
      author: data.author.present ? data.author.value : this.author,
      description:
          data.description.present ? data.description.value : this.description,
      genre: data.genre.present ? data.genre.value : this.genre,
      title: data.title.present ? data.title.value : this.title,
      status: data.status.present ? data.status.value : this.status,
      thumbnailUrl: data.thumbnailUrl.present
          ? data.thumbnailUrl.value
          : this.thumbnailUrl,
      favorite: data.favorite.present ? data.favorite.value : this.favorite,
      lastUpdate:
          data.lastUpdate.present ? data.lastUpdate.value : this.lastUpdate,
      nextUpdate:
          data.nextUpdate.present ? data.nextUpdate.value : this.nextUpdate,
      initialized:
          data.initialized.present ? data.initialized.value : this.initialized,
      viewer: data.viewer.present ? data.viewer.value : this.viewer,
      chapterFlags: data.chapterFlags.present
          ? data.chapterFlags.value
          : this.chapterFlags,
      coverLastModified: data.coverLastModified.present
          ? data.coverLastModified.value
          : this.coverLastModified,
      dateAdded: data.dateAdded.present ? data.dateAdded.value : this.dateAdded,
      updateStrategy: data.updateStrategy.present
          ? data.updateStrategy.value
          : this.updateStrategy,
      calculateInterval: data.calculateInterval.present
          ? data.calculateInterval.value
          : this.calculateInterval,
      lastModifiedAt: data.lastModifiedAt.present
          ? data.lastModifiedAt.value
          : this.lastModifiedAt,
      favoriteModifiedAt: data.favoriteModifiedAt.present
          ? data.favoriteModifiedAt.value
          : this.favoriteModifiedAt,
      version: data.version.present ? data.version.value : this.version,
      isSyncing: data.isSyncing.present ? data.isSyncing.value : this.isSyncing,
      notes: data.notes.present ? data.notes.value : this.notes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Manga(')
          ..write('id: $id, ')
          ..write('source: $source, ')
          ..write('url: $url, ')
          ..write('artist: $artist, ')
          ..write('author: $author, ')
          ..write('description: $description, ')
          ..write('genre: $genre, ')
          ..write('title: $title, ')
          ..write('status: $status, ')
          ..write('thumbnailUrl: $thumbnailUrl, ')
          ..write('favorite: $favorite, ')
          ..write('lastUpdate: $lastUpdate, ')
          ..write('nextUpdate: $nextUpdate, ')
          ..write('initialized: $initialized, ')
          ..write('viewer: $viewer, ')
          ..write('chapterFlags: $chapterFlags, ')
          ..write('coverLastModified: $coverLastModified, ')
          ..write('dateAdded: $dateAdded, ')
          ..write('updateStrategy: $updateStrategy, ')
          ..write('calculateInterval: $calculateInterval, ')
          ..write('lastModifiedAt: $lastModifiedAt, ')
          ..write('favoriteModifiedAt: $favoriteModifiedAt, ')
          ..write('version: $version, ')
          ..write('isSyncing: $isSyncing, ')
          ..write('notes: $notes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        source,
        url,
        artist,
        author,
        description,
        genre,
        title,
        status,
        thumbnailUrl,
        favorite,
        lastUpdate,
        nextUpdate,
        initialized,
        viewer,
        chapterFlags,
        coverLastModified,
        dateAdded,
        updateStrategy,
        calculateInterval,
        lastModifiedAt,
        favoriteModifiedAt,
        version,
        isSyncing,
        notes
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Manga &&
          other.id == this.id &&
          other.source == this.source &&
          other.url == this.url &&
          other.artist == this.artist &&
          other.author == this.author &&
          other.description == this.description &&
          other.genre == this.genre &&
          other.title == this.title &&
          other.status == this.status &&
          other.thumbnailUrl == this.thumbnailUrl &&
          other.favorite == this.favorite &&
          other.lastUpdate == this.lastUpdate &&
          other.nextUpdate == this.nextUpdate &&
          other.initialized == this.initialized &&
          other.viewer == this.viewer &&
          other.chapterFlags == this.chapterFlags &&
          other.coverLastModified == this.coverLastModified &&
          other.dateAdded == this.dateAdded &&
          other.updateStrategy == this.updateStrategy &&
          other.calculateInterval == this.calculateInterval &&
          other.lastModifiedAt == this.lastModifiedAt &&
          other.favoriteModifiedAt == this.favoriteModifiedAt &&
          other.version == this.version &&
          other.isSyncing == this.isSyncing &&
          other.notes == this.notes);
}

class MangasCompanion extends UpdateCompanion<Manga> {
  final Value<int> id;
  final Value<int> source;
  final Value<String> url;
  final Value<String?> artist;
  final Value<String?> author;
  final Value<String?> description;
  final Value<String?> genre;
  final Value<String> title;
  final Value<int> status;
  final Value<String?> thumbnailUrl;
  final Value<int> favorite;
  final Value<int?> lastUpdate;
  final Value<int?> nextUpdate;
  final Value<int> initialized;
  final Value<int> viewer;
  final Value<int> chapterFlags;
  final Value<int> coverLastModified;
  final Value<int> dateAdded;
  final Value<int> updateStrategy;
  final Value<int> calculateInterval;
  final Value<int> lastModifiedAt;
  final Value<int?> favoriteModifiedAt;
  final Value<int> version;
  final Value<int> isSyncing;
  final Value<String> notes;
  const MangasCompanion({
    this.id = const Value.absent(),
    this.source = const Value.absent(),
    this.url = const Value.absent(),
    this.artist = const Value.absent(),
    this.author = const Value.absent(),
    this.description = const Value.absent(),
    this.genre = const Value.absent(),
    this.title = const Value.absent(),
    this.status = const Value.absent(),
    this.thumbnailUrl = const Value.absent(),
    this.favorite = const Value.absent(),
    this.lastUpdate = const Value.absent(),
    this.nextUpdate = const Value.absent(),
    this.initialized = const Value.absent(),
    this.viewer = const Value.absent(),
    this.chapterFlags = const Value.absent(),
    this.coverLastModified = const Value.absent(),
    this.dateAdded = const Value.absent(),
    this.updateStrategy = const Value.absent(),
    this.calculateInterval = const Value.absent(),
    this.lastModifiedAt = const Value.absent(),
    this.favoriteModifiedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.isSyncing = const Value.absent(),
    this.notes = const Value.absent(),
  });
  MangasCompanion.insert({
    this.id = const Value.absent(),
    required int source,
    required String url,
    this.artist = const Value.absent(),
    this.author = const Value.absent(),
    this.description = const Value.absent(),
    this.genre = const Value.absent(),
    required String title,
    required int status,
    this.thumbnailUrl = const Value.absent(),
    required int favorite,
    this.lastUpdate = const Value.absent(),
    this.nextUpdate = const Value.absent(),
    required int initialized,
    required int viewer,
    required int chapterFlags,
    required int coverLastModified,
    required int dateAdded,
    this.updateStrategy = const Value.absent(),
    this.calculateInterval = const Value.absent(),
    this.lastModifiedAt = const Value.absent(),
    this.favoriteModifiedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.isSyncing = const Value.absent(),
    this.notes = const Value.absent(),
  })  : source = Value(source),
        url = Value(url),
        title = Value(title),
        status = Value(status),
        favorite = Value(favorite),
        initialized = Value(initialized),
        viewer = Value(viewer),
        chapterFlags = Value(chapterFlags),
        coverLastModified = Value(coverLastModified),
        dateAdded = Value(dateAdded);
  static Insertable<Manga> custom({
    Expression<int>? id,
    Expression<int>? source,
    Expression<String>? url,
    Expression<String>? artist,
    Expression<String>? author,
    Expression<String>? description,
    Expression<String>? genre,
    Expression<String>? title,
    Expression<int>? status,
    Expression<String>? thumbnailUrl,
    Expression<int>? favorite,
    Expression<int>? lastUpdate,
    Expression<int>? nextUpdate,
    Expression<int>? initialized,
    Expression<int>? viewer,
    Expression<int>? chapterFlags,
    Expression<int>? coverLastModified,
    Expression<int>? dateAdded,
    Expression<int>? updateStrategy,
    Expression<int>? calculateInterval,
    Expression<int>? lastModifiedAt,
    Expression<int>? favoriteModifiedAt,
    Expression<int>? version,
    Expression<int>? isSyncing,
    Expression<String>? notes,
  }) {
    return RawValuesInsertable({
      if (id != null) '_id': id,
      if (source != null) 'source': source,
      if (url != null) 'url': url,
      if (artist != null) 'artist': artist,
      if (author != null) 'author': author,
      if (description != null) 'description': description,
      if (genre != null) 'genre': genre,
      if (title != null) 'title': title,
      if (status != null) 'status': status,
      if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      if (favorite != null) 'favorite': favorite,
      if (lastUpdate != null) 'last_update': lastUpdate,
      if (nextUpdate != null) 'next_update': nextUpdate,
      if (initialized != null) 'initialized': initialized,
      if (viewer != null) 'viewer': viewer,
      if (chapterFlags != null) 'chapter_flags': chapterFlags,
      if (coverLastModified != null) 'cover_last_modified': coverLastModified,
      if (dateAdded != null) 'date_added': dateAdded,
      if (updateStrategy != null) 'update_strategy': updateStrategy,
      if (calculateInterval != null) 'calculate_interval': calculateInterval,
      if (lastModifiedAt != null) 'last_modified_at': lastModifiedAt,
      if (favoriteModifiedAt != null)
        'favorite_modified_at': favoriteModifiedAt,
      if (version != null) 'version': version,
      if (isSyncing != null) 'is_syncing': isSyncing,
      if (notes != null) 'notes': notes,
    });
  }

  MangasCompanion copyWith(
      {Value<int>? id,
      Value<int>? source,
      Value<String>? url,
      Value<String?>? artist,
      Value<String?>? author,
      Value<String?>? description,
      Value<String?>? genre,
      Value<String>? title,
      Value<int>? status,
      Value<String?>? thumbnailUrl,
      Value<int>? favorite,
      Value<int?>? lastUpdate,
      Value<int?>? nextUpdate,
      Value<int>? initialized,
      Value<int>? viewer,
      Value<int>? chapterFlags,
      Value<int>? coverLastModified,
      Value<int>? dateAdded,
      Value<int>? updateStrategy,
      Value<int>? calculateInterval,
      Value<int>? lastModifiedAt,
      Value<int?>? favoriteModifiedAt,
      Value<int>? version,
      Value<int>? isSyncing,
      Value<String>? notes}) {
    return MangasCompanion(
      id: id ?? this.id,
      source: source ?? this.source,
      url: url ?? this.url,
      artist: artist ?? this.artist,
      author: author ?? this.author,
      description: description ?? this.description,
      genre: genre ?? this.genre,
      title: title ?? this.title,
      status: status ?? this.status,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      favorite: favorite ?? this.favorite,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      nextUpdate: nextUpdate ?? this.nextUpdate,
      initialized: initialized ?? this.initialized,
      viewer: viewer ?? this.viewer,
      chapterFlags: chapterFlags ?? this.chapterFlags,
      coverLastModified: coverLastModified ?? this.coverLastModified,
      dateAdded: dateAdded ?? this.dateAdded,
      updateStrategy: updateStrategy ?? this.updateStrategy,
      calculateInterval: calculateInterval ?? this.calculateInterval,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      favoriteModifiedAt: favoriteModifiedAt ?? this.favoriteModifiedAt,
      version: version ?? this.version,
      isSyncing: isSyncing ?? this.isSyncing,
      notes: notes ?? this.notes,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['_id'] = Variable<int>(id.value);
    }
    if (source.present) {
      map['source'] = Variable<int>(source.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (genre.present) {
      map['genre'] = Variable<String>(genre.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (thumbnailUrl.present) {
      map['thumbnail_url'] = Variable<String>(thumbnailUrl.value);
    }
    if (favorite.present) {
      map['favorite'] = Variable<int>(favorite.value);
    }
    if (lastUpdate.present) {
      map['last_update'] = Variable<int>(lastUpdate.value);
    }
    if (nextUpdate.present) {
      map['next_update'] = Variable<int>(nextUpdate.value);
    }
    if (initialized.present) {
      map['initialized'] = Variable<int>(initialized.value);
    }
    if (viewer.present) {
      map['viewer'] = Variable<int>(viewer.value);
    }
    if (chapterFlags.present) {
      map['chapter_flags'] = Variable<int>(chapterFlags.value);
    }
    if (coverLastModified.present) {
      map['cover_last_modified'] = Variable<int>(coverLastModified.value);
    }
    if (dateAdded.present) {
      map['date_added'] = Variable<int>(dateAdded.value);
    }
    if (updateStrategy.present) {
      map['update_strategy'] = Variable<int>(updateStrategy.value);
    }
    if (calculateInterval.present) {
      map['calculate_interval'] = Variable<int>(calculateInterval.value);
    }
    if (lastModifiedAt.present) {
      map['last_modified_at'] = Variable<int>(lastModifiedAt.value);
    }
    if (favoriteModifiedAt.present) {
      map['favorite_modified_at'] = Variable<int>(favoriteModifiedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (isSyncing.present) {
      map['is_syncing'] = Variable<int>(isSyncing.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MangasCompanion(')
          ..write('id: $id, ')
          ..write('source: $source, ')
          ..write('url: $url, ')
          ..write('artist: $artist, ')
          ..write('author: $author, ')
          ..write('description: $description, ')
          ..write('genre: $genre, ')
          ..write('title: $title, ')
          ..write('status: $status, ')
          ..write('thumbnailUrl: $thumbnailUrl, ')
          ..write('favorite: $favorite, ')
          ..write('lastUpdate: $lastUpdate, ')
          ..write('nextUpdate: $nextUpdate, ')
          ..write('initialized: $initialized, ')
          ..write('viewer: $viewer, ')
          ..write('chapterFlags: $chapterFlags, ')
          ..write('coverLastModified: $coverLastModified, ')
          ..write('dateAdded: $dateAdded, ')
          ..write('updateStrategy: $updateStrategy, ')
          ..write('calculateInterval: $calculateInterval, ')
          ..write('lastModifiedAt: $lastModifiedAt, ')
          ..write('favoriteModifiedAt: $favoriteModifiedAt, ')
          ..write('version: $version, ')
          ..write('isSyncing: $isSyncing, ')
          ..write('notes: $notes')
          ..write(')'))
        .toString();
  }
}

class MangaLinks extends Table with TableInfo<MangaLinks, MangaLink> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  MangaLinks(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _primaryMangaIdMeta =
      const VerificationMeta('primaryMangaId');
  late final GeneratedColumn<int> primaryMangaId = GeneratedColumn<int>(
      'primary_manga_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _linkedMangaIdMeta =
      const VerificationMeta('linkedMangaId');
  late final GeneratedColumn<int> linkedMangaId = GeneratedColumn<int>(
      'linked_manga_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _priorityMeta =
      const VerificationMeta('priority');
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
      'priority', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT 0',
      defaultValue: const CustomExpression('0'));
  @override
  List<GeneratedColumn> get $columns =>
      [primaryMangaId, linkedMangaId, priority];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'manga_links';
  @override
  VerificationContext validateIntegrity(Insertable<MangaLink> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('primary_manga_id')) {
      context.handle(
          _primaryMangaIdMeta,
          primaryMangaId.isAcceptableOrUnknown(
              data['primary_manga_id']!, _primaryMangaIdMeta));
    } else if (isInserting) {
      context.missing(_primaryMangaIdMeta);
    }
    if (data.containsKey('linked_manga_id')) {
      context.handle(
          _linkedMangaIdMeta,
          linkedMangaId.isAcceptableOrUnknown(
              data['linked_manga_id']!, _linkedMangaIdMeta));
    } else if (isInserting) {
      context.missing(_linkedMangaIdMeta);
    }
    if (data.containsKey('priority')) {
      context.handle(_priorityMeta,
          priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {primaryMangaId, linkedMangaId};
  @override
  MangaLink map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MangaLink(
      primaryMangaId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}primary_manga_id'])!,
      linkedMangaId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}linked_manga_id'])!,
      priority: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}priority'])!,
    );
  }

  @override
  MangaLinks createAlias(String alias) {
    return MangaLinks(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
        'PRIMARY KEY(primary_manga_id, linked_manga_id)',
        'FOREIGN KEY(primary_manga_id)REFERENCES mangas(_id)ON DELETE CASCADE',
        'FOREIGN KEY(linked_manga_id)REFERENCES mangas(_id)ON DELETE CASCADE'
      ];
  @override
  bool get dontWriteConstraints => true;
}

class MangaLink extends DataClass implements Insertable<MangaLink> {
  final int primaryMangaId;
  final int linkedMangaId;
  final int priority;
  const MangaLink(
      {required this.primaryMangaId,
      required this.linkedMangaId,
      required this.priority});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['primary_manga_id'] = Variable<int>(primaryMangaId);
    map['linked_manga_id'] = Variable<int>(linkedMangaId);
    map['priority'] = Variable<int>(priority);
    return map;
  }

  MangaLinksCompanion toCompanion(bool nullToAbsent) {
    return MangaLinksCompanion(
      primaryMangaId: Value(primaryMangaId),
      linkedMangaId: Value(linkedMangaId),
      priority: Value(priority),
    );
  }

  factory MangaLink.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MangaLink(
      primaryMangaId: serializer.fromJson<int>(json['primary_manga_id']),
      linkedMangaId: serializer.fromJson<int>(json['linked_manga_id']),
      priority: serializer.fromJson<int>(json['priority']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'primary_manga_id': serializer.toJson<int>(primaryMangaId),
      'linked_manga_id': serializer.toJson<int>(linkedMangaId),
      'priority': serializer.toJson<int>(priority),
    };
  }

  MangaLink copyWith(
          {int? primaryMangaId, int? linkedMangaId, int? priority}) =>
      MangaLink(
        primaryMangaId: primaryMangaId ?? this.primaryMangaId,
        linkedMangaId: linkedMangaId ?? this.linkedMangaId,
        priority: priority ?? this.priority,
      );
  MangaLink copyWithCompanion(MangaLinksCompanion data) {
    return MangaLink(
      primaryMangaId: data.primaryMangaId.present
          ? data.primaryMangaId.value
          : this.primaryMangaId,
      linkedMangaId: data.linkedMangaId.present
          ? data.linkedMangaId.value
          : this.linkedMangaId,
      priority: data.priority.present ? data.priority.value : this.priority,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MangaLink(')
          ..write('primaryMangaId: $primaryMangaId, ')
          ..write('linkedMangaId: $linkedMangaId, ')
          ..write('priority: $priority')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(primaryMangaId, linkedMangaId, priority);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MangaLink &&
          other.primaryMangaId == this.primaryMangaId &&
          other.linkedMangaId == this.linkedMangaId &&
          other.priority == this.priority);
}

class MangaLinksCompanion extends UpdateCompanion<MangaLink> {
  final Value<int> primaryMangaId;
  final Value<int> linkedMangaId;
  final Value<int> priority;
  final Value<int> rowid;
  const MangaLinksCompanion({
    this.primaryMangaId = const Value.absent(),
    this.linkedMangaId = const Value.absent(),
    this.priority = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MangaLinksCompanion.insert({
    required int primaryMangaId,
    required int linkedMangaId,
    this.priority = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : primaryMangaId = Value(primaryMangaId),
        linkedMangaId = Value(linkedMangaId);
  static Insertable<MangaLink> custom({
    Expression<int>? primaryMangaId,
    Expression<int>? linkedMangaId,
    Expression<int>? priority,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (primaryMangaId != null) 'primary_manga_id': primaryMangaId,
      if (linkedMangaId != null) 'linked_manga_id': linkedMangaId,
      if (priority != null) 'priority': priority,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MangaLinksCompanion copyWith(
      {Value<int>? primaryMangaId,
      Value<int>? linkedMangaId,
      Value<int>? priority,
      Value<int>? rowid}) {
    return MangaLinksCompanion(
      primaryMangaId: primaryMangaId ?? this.primaryMangaId,
      linkedMangaId: linkedMangaId ?? this.linkedMangaId,
      priority: priority ?? this.priority,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (primaryMangaId.present) {
      map['primary_manga_id'] = Variable<int>(primaryMangaId.value);
    }
    if (linkedMangaId.present) {
      map['linked_manga_id'] = Variable<int>(linkedMangaId.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MangaLinksCompanion(')
          ..write('primaryMangaId: $primaryMangaId, ')
          ..write('linkedMangaId: $linkedMangaId, ')
          ..write('priority: $priority, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class ExtensionRepos extends Table
    with TableInfo<ExtensionRepos, ExtensionRepo> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ExtensionRepos(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _baseUrlMeta =
      const VerificationMeta('baseUrl');
  late final GeneratedColumn<String> baseUrl = GeneratedColumn<String>(
      'base_url', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL PRIMARY KEY');
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _shortNameMeta =
      const VerificationMeta('shortName');
  late final GeneratedColumn<String> shortName = GeneratedColumn<String>(
      'short_name', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  static const VerificationMeta _websiteMeta =
      const VerificationMeta('website');
  late final GeneratedColumn<String> website = GeneratedColumn<String>(
      'website', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _signingKeyFingerprintMeta =
      const VerificationMeta('signingKeyFingerprint');
  late final GeneratedColumn<String> signingKeyFingerprint =
      GeneratedColumn<String>('signing_key_fingerprint', aliasedName, false,
          type: DriftSqlType.string,
          requiredDuringInsert: true,
          $customConstraints: 'UNIQUE NOT NULL');
  @override
  List<GeneratedColumn> get $columns =>
      [baseUrl, name, shortName, website, signingKeyFingerprint];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'extension_repos';
  @override
  VerificationContext validateIntegrity(Insertable<ExtensionRepo> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('base_url')) {
      context.handle(_baseUrlMeta,
          baseUrl.isAcceptableOrUnknown(data['base_url']!, _baseUrlMeta));
    } else if (isInserting) {
      context.missing(_baseUrlMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('short_name')) {
      context.handle(_shortNameMeta,
          shortName.isAcceptableOrUnknown(data['short_name']!, _shortNameMeta));
    }
    if (data.containsKey('website')) {
      context.handle(_websiteMeta,
          website.isAcceptableOrUnknown(data['website']!, _websiteMeta));
    } else if (isInserting) {
      context.missing(_websiteMeta);
    }
    if (data.containsKey('signing_key_fingerprint')) {
      context.handle(
          _signingKeyFingerprintMeta,
          signingKeyFingerprint.isAcceptableOrUnknown(
              data['signing_key_fingerprint']!, _signingKeyFingerprintMeta));
    } else if (isInserting) {
      context.missing(_signingKeyFingerprintMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {baseUrl};
  @override
  ExtensionRepo map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExtensionRepo(
      baseUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}base_url'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      shortName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}short_name']),
      website: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}website'])!,
      signingKeyFingerprint: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}signing_key_fingerprint'])!,
    );
  }

  @override
  ExtensionRepos createAlias(String alias) {
    return ExtensionRepos(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class ExtensionRepo extends DataClass implements Insertable<ExtensionRepo> {
  final String baseUrl;
  final String name;
  final String? shortName;
  final String website;
  final String signingKeyFingerprint;
  const ExtensionRepo(
      {required this.baseUrl,
      required this.name,
      this.shortName,
      required this.website,
      required this.signingKeyFingerprint});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['base_url'] = Variable<String>(baseUrl);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || shortName != null) {
      map['short_name'] = Variable<String>(shortName);
    }
    map['website'] = Variable<String>(website);
    map['signing_key_fingerprint'] = Variable<String>(signingKeyFingerprint);
    return map;
  }

  ExtensionReposCompanion toCompanion(bool nullToAbsent) {
    return ExtensionReposCompanion(
      baseUrl: Value(baseUrl),
      name: Value(name),
      shortName: shortName == null && nullToAbsent
          ? const Value.absent()
          : Value(shortName),
      website: Value(website),
      signingKeyFingerprint: Value(signingKeyFingerprint),
    );
  }

  factory ExtensionRepo.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExtensionRepo(
      baseUrl: serializer.fromJson<String>(json['base_url']),
      name: serializer.fromJson<String>(json['name']),
      shortName: serializer.fromJson<String?>(json['short_name']),
      website: serializer.fromJson<String>(json['website']),
      signingKeyFingerprint:
          serializer.fromJson<String>(json['signing_key_fingerprint']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'base_url': serializer.toJson<String>(baseUrl),
      'name': serializer.toJson<String>(name),
      'short_name': serializer.toJson<String?>(shortName),
      'website': serializer.toJson<String>(website),
      'signing_key_fingerprint':
          serializer.toJson<String>(signingKeyFingerprint),
    };
  }

  ExtensionRepo copyWith(
          {String? baseUrl,
          String? name,
          Value<String?> shortName = const Value.absent(),
          String? website,
          String? signingKeyFingerprint}) =>
      ExtensionRepo(
        baseUrl: baseUrl ?? this.baseUrl,
        name: name ?? this.name,
        shortName: shortName.present ? shortName.value : this.shortName,
        website: website ?? this.website,
        signingKeyFingerprint:
            signingKeyFingerprint ?? this.signingKeyFingerprint,
      );
  ExtensionRepo copyWithCompanion(ExtensionReposCompanion data) {
    return ExtensionRepo(
      baseUrl: data.baseUrl.present ? data.baseUrl.value : this.baseUrl,
      name: data.name.present ? data.name.value : this.name,
      shortName: data.shortName.present ? data.shortName.value : this.shortName,
      website: data.website.present ? data.website.value : this.website,
      signingKeyFingerprint: data.signingKeyFingerprint.present
          ? data.signingKeyFingerprint.value
          : this.signingKeyFingerprint,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExtensionRepo(')
          ..write('baseUrl: $baseUrl, ')
          ..write('name: $name, ')
          ..write('shortName: $shortName, ')
          ..write('website: $website, ')
          ..write('signingKeyFingerprint: $signingKeyFingerprint')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(baseUrl, name, shortName, website, signingKeyFingerprint);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExtensionRepo &&
          other.baseUrl == this.baseUrl &&
          other.name == this.name &&
          other.shortName == this.shortName &&
          other.website == this.website &&
          other.signingKeyFingerprint == this.signingKeyFingerprint);
}

class ExtensionReposCompanion extends UpdateCompanion<ExtensionRepo> {
  final Value<String> baseUrl;
  final Value<String> name;
  final Value<String?> shortName;
  final Value<String> website;
  final Value<String> signingKeyFingerprint;
  final Value<int> rowid;
  const ExtensionReposCompanion({
    this.baseUrl = const Value.absent(),
    this.name = const Value.absent(),
    this.shortName = const Value.absent(),
    this.website = const Value.absent(),
    this.signingKeyFingerprint = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExtensionReposCompanion.insert({
    required String baseUrl,
    required String name,
    this.shortName = const Value.absent(),
    required String website,
    required String signingKeyFingerprint,
    this.rowid = const Value.absent(),
  })  : baseUrl = Value(baseUrl),
        name = Value(name),
        website = Value(website),
        signingKeyFingerprint = Value(signingKeyFingerprint);
  static Insertable<ExtensionRepo> custom({
    Expression<String>? baseUrl,
    Expression<String>? name,
    Expression<String>? shortName,
    Expression<String>? website,
    Expression<String>? signingKeyFingerprint,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (baseUrl != null) 'base_url': baseUrl,
      if (name != null) 'name': name,
      if (shortName != null) 'short_name': shortName,
      if (website != null) 'website': website,
      if (signingKeyFingerprint != null)
        'signing_key_fingerprint': signingKeyFingerprint,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExtensionReposCompanion copyWith(
      {Value<String>? baseUrl,
      Value<String>? name,
      Value<String?>? shortName,
      Value<String>? website,
      Value<String>? signingKeyFingerprint,
      Value<int>? rowid}) {
    return ExtensionReposCompanion(
      baseUrl: baseUrl ?? this.baseUrl,
      name: name ?? this.name,
      shortName: shortName ?? this.shortName,
      website: website ?? this.website,
      signingKeyFingerprint:
          signingKeyFingerprint ?? this.signingKeyFingerprint,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (baseUrl.present) {
      map['base_url'] = Variable<String>(baseUrl.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (shortName.present) {
      map['short_name'] = Variable<String>(shortName.value);
    }
    if (website.present) {
      map['website'] = Variable<String>(website.value);
    }
    if (signingKeyFingerprint.present) {
      map['signing_key_fingerprint'] =
          Variable<String>(signingKeyFingerprint.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExtensionReposCompanion(')
          ..write('baseUrl: $baseUrl, ')
          ..write('name: $name, ')
          ..write('shortName: $shortName, ')
          ..write('website: $website, ')
          ..write('signingKeyFingerprint: $signingKeyFingerprint, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class ScanlatorPriority extends Table
    with TableInfo<ScanlatorPriority, ScanlatorPriorityData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ScanlatorPriority(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mangaIdMeta =
      const VerificationMeta('mangaId');
  late final GeneratedColumn<int> mangaId = GeneratedColumn<int>(
      'manga_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _scanlatorMeta =
      const VerificationMeta('scanlator');
  late final GeneratedColumn<String> scanlator = GeneratedColumn<String>(
      'scanlator', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _priorityMeta =
      const VerificationMeta('priority');
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
      'priority', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  @override
  List<GeneratedColumn> get $columns => [mangaId, scanlator, priority];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scanlator_priority';
  @override
  VerificationContext validateIntegrity(
      Insertable<ScanlatorPriorityData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('manga_id')) {
      context.handle(_mangaIdMeta,
          mangaId.isAcceptableOrUnknown(data['manga_id']!, _mangaIdMeta));
    } else if (isInserting) {
      context.missing(_mangaIdMeta);
    }
    if (data.containsKey('scanlator')) {
      context.handle(_scanlatorMeta,
          scanlator.isAcceptableOrUnknown(data['scanlator']!, _scanlatorMeta));
    } else if (isInserting) {
      context.missing(_scanlatorMeta);
    }
    if (data.containsKey('priority')) {
      context.handle(_priorityMeta,
          priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta));
    } else if (isInserting) {
      context.missing(_priorityMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mangaId, scanlator};
  @override
  ScanlatorPriorityData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScanlatorPriorityData(
      mangaId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}manga_id'])!,
      scanlator: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}scanlator'])!,
      priority: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}priority'])!,
    );
  }

  @override
  ScanlatorPriority createAlias(String alias) {
    return ScanlatorPriority(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
        'PRIMARY KEY(manga_id, scanlator)',
        'FOREIGN KEY(manga_id)REFERENCES mangas(_id)ON DELETE CASCADE'
      ];
  @override
  bool get dontWriteConstraints => true;
}

class ScanlatorPriorityData extends DataClass
    implements Insertable<ScanlatorPriorityData> {
  final int mangaId;
  final String scanlator;
  final int priority;
  const ScanlatorPriorityData(
      {required this.mangaId, required this.scanlator, required this.priority});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['manga_id'] = Variable<int>(mangaId);
    map['scanlator'] = Variable<String>(scanlator);
    map['priority'] = Variable<int>(priority);
    return map;
  }

  ScanlatorPriorityCompanion toCompanion(bool nullToAbsent) {
    return ScanlatorPriorityCompanion(
      mangaId: Value(mangaId),
      scanlator: Value(scanlator),
      priority: Value(priority),
    );
  }

  factory ScanlatorPriorityData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScanlatorPriorityData(
      mangaId: serializer.fromJson<int>(json['manga_id']),
      scanlator: serializer.fromJson<String>(json['scanlator']),
      priority: serializer.fromJson<int>(json['priority']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'manga_id': serializer.toJson<int>(mangaId),
      'scanlator': serializer.toJson<String>(scanlator),
      'priority': serializer.toJson<int>(priority),
    };
  }

  ScanlatorPriorityData copyWith(
          {int? mangaId, String? scanlator, int? priority}) =>
      ScanlatorPriorityData(
        mangaId: mangaId ?? this.mangaId,
        scanlator: scanlator ?? this.scanlator,
        priority: priority ?? this.priority,
      );
  ScanlatorPriorityData copyWithCompanion(ScanlatorPriorityCompanion data) {
    return ScanlatorPriorityData(
      mangaId: data.mangaId.present ? data.mangaId.value : this.mangaId,
      scanlator: data.scanlator.present ? data.scanlator.value : this.scanlator,
      priority: data.priority.present ? data.priority.value : this.priority,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScanlatorPriorityData(')
          ..write('mangaId: $mangaId, ')
          ..write('scanlator: $scanlator, ')
          ..write('priority: $priority')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(mangaId, scanlator, priority);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScanlatorPriorityData &&
          other.mangaId == this.mangaId &&
          other.scanlator == this.scanlator &&
          other.priority == this.priority);
}

class ScanlatorPriorityCompanion
    extends UpdateCompanion<ScanlatorPriorityData> {
  final Value<int> mangaId;
  final Value<String> scanlator;
  final Value<int> priority;
  final Value<int> rowid;
  const ScanlatorPriorityCompanion({
    this.mangaId = const Value.absent(),
    this.scanlator = const Value.absent(),
    this.priority = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ScanlatorPriorityCompanion.insert({
    required int mangaId,
    required String scanlator,
    required int priority,
    this.rowid = const Value.absent(),
  })  : mangaId = Value(mangaId),
        scanlator = Value(scanlator),
        priority = Value(priority);
  static Insertable<ScanlatorPriorityData> custom({
    Expression<int>? mangaId,
    Expression<String>? scanlator,
    Expression<int>? priority,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mangaId != null) 'manga_id': mangaId,
      if (scanlator != null) 'scanlator': scanlator,
      if (priority != null) 'priority': priority,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ScanlatorPriorityCompanion copyWith(
      {Value<int>? mangaId,
      Value<String>? scanlator,
      Value<int>? priority,
      Value<int>? rowid}) {
    return ScanlatorPriorityCompanion(
      mangaId: mangaId ?? this.mangaId,
      scanlator: scanlator ?? this.scanlator,
      priority: priority ?? this.priority,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mangaId.present) {
      map['manga_id'] = Variable<int>(mangaId.value);
    }
    if (scanlator.present) {
      map['scanlator'] = Variable<String>(scanlator.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScanlatorPriorityCompanion(')
          ..write('mangaId: $mangaId, ')
          ..write('scanlator: $scanlator, ')
          ..write('priority: $priority, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class ExcludedScanlators extends Table
    with TableInfo<ExcludedScanlators, ExcludedScanlator> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ExcludedScanlators(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mangaIdMeta =
      const VerificationMeta('mangaId');
  late final GeneratedColumn<int> mangaId = GeneratedColumn<int>(
      'manga_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _scanlatorMeta =
      const VerificationMeta('scanlator');
  late final GeneratedColumn<String> scanlator = GeneratedColumn<String>(
      'scanlator', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  @override
  List<GeneratedColumn> get $columns => [mangaId, scanlator];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'excluded_scanlators';
  @override
  VerificationContext validateIntegrity(Insertable<ExcludedScanlator> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('manga_id')) {
      context.handle(_mangaIdMeta,
          mangaId.isAcceptableOrUnknown(data['manga_id']!, _mangaIdMeta));
    } else if (isInserting) {
      context.missing(_mangaIdMeta);
    }
    if (data.containsKey('scanlator')) {
      context.handle(_scanlatorMeta,
          scanlator.isAcceptableOrUnknown(data['scanlator']!, _scanlatorMeta));
    } else if (isInserting) {
      context.missing(_scanlatorMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  ExcludedScanlator map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExcludedScanlator(
      mangaId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}manga_id'])!,
      scanlator: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}scanlator'])!,
    );
  }

  @override
  ExcludedScanlators createAlias(String alias) {
    return ExcludedScanlators(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints =>
      const ['FOREIGN KEY(manga_id)REFERENCES mangas(_id)ON DELETE CASCADE'];
  @override
  bool get dontWriteConstraints => true;
}

class ExcludedScanlator extends DataClass
    implements Insertable<ExcludedScanlator> {
  final int mangaId;
  final String scanlator;
  const ExcludedScanlator({required this.mangaId, required this.scanlator});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['manga_id'] = Variable<int>(mangaId);
    map['scanlator'] = Variable<String>(scanlator);
    return map;
  }

  ExcludedScanlatorsCompanion toCompanion(bool nullToAbsent) {
    return ExcludedScanlatorsCompanion(
      mangaId: Value(mangaId),
      scanlator: Value(scanlator),
    );
  }

  factory ExcludedScanlator.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExcludedScanlator(
      mangaId: serializer.fromJson<int>(json['manga_id']),
      scanlator: serializer.fromJson<String>(json['scanlator']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'manga_id': serializer.toJson<int>(mangaId),
      'scanlator': serializer.toJson<String>(scanlator),
    };
  }

  ExcludedScanlator copyWith({int? mangaId, String? scanlator}) =>
      ExcludedScanlator(
        mangaId: mangaId ?? this.mangaId,
        scanlator: scanlator ?? this.scanlator,
      );
  ExcludedScanlator copyWithCompanion(ExcludedScanlatorsCompanion data) {
    return ExcludedScanlator(
      mangaId: data.mangaId.present ? data.mangaId.value : this.mangaId,
      scanlator: data.scanlator.present ? data.scanlator.value : this.scanlator,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExcludedScanlator(')
          ..write('mangaId: $mangaId, ')
          ..write('scanlator: $scanlator')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(mangaId, scanlator);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExcludedScanlator &&
          other.mangaId == this.mangaId &&
          other.scanlator == this.scanlator);
}

class ExcludedScanlatorsCompanion extends UpdateCompanion<ExcludedScanlator> {
  final Value<int> mangaId;
  final Value<String> scanlator;
  final Value<int> rowid;
  const ExcludedScanlatorsCompanion({
    this.mangaId = const Value.absent(),
    this.scanlator = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExcludedScanlatorsCompanion.insert({
    required int mangaId,
    required String scanlator,
    this.rowid = const Value.absent(),
  })  : mangaId = Value(mangaId),
        scanlator = Value(scanlator);
  static Insertable<ExcludedScanlator> custom({
    Expression<int>? mangaId,
    Expression<String>? scanlator,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mangaId != null) 'manga_id': mangaId,
      if (scanlator != null) 'scanlator': scanlator,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExcludedScanlatorsCompanion copyWith(
      {Value<int>? mangaId, Value<String>? scanlator, Value<int>? rowid}) {
    return ExcludedScanlatorsCompanion(
      mangaId: mangaId ?? this.mangaId,
      scanlator: scanlator ?? this.scanlator,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mangaId.present) {
      map['manga_id'] = Variable<int>(mangaId.value);
    }
    if (scanlator.present) {
      map['scanlator'] = Variable<String>(scanlator.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExcludedScanlatorsCompanion(')
          ..write('mangaId: $mangaId, ')
          ..write('scanlator: $scanlator, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Sources extends Table with TableInfo<Sources, Source> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Sources(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      '_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL PRIMARY KEY');
  static const VerificationMeta _langMeta = const VerificationMeta('lang');
  late final GeneratedColumn<String> lang = GeneratedColumn<String>(
      'lang', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  @override
  List<GeneratedColumn> get $columns => [id, lang, name];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sources';
  @override
  VerificationContext validateIntegrity(Insertable<Source> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('_id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['_id']!, _idMeta));
    }
    if (data.containsKey('lang')) {
      context.handle(
          _langMeta, lang.isAcceptableOrUnknown(data['lang']!, _langMeta));
    } else if (isInserting) {
      context.missing(_langMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Source map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Source(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}_id'])!,
      lang: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}lang'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
    );
  }

  @override
  Sources createAlias(String alias) {
    return Sources(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class Source extends DataClass implements Insertable<Source> {
  final int id;
  final String lang;
  final String name;
  const Source({required this.id, required this.lang, required this.name});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['_id'] = Variable<int>(id);
    map['lang'] = Variable<String>(lang);
    map['name'] = Variable<String>(name);
    return map;
  }

  SourcesCompanion toCompanion(bool nullToAbsent) {
    return SourcesCompanion(
      id: Value(id),
      lang: Value(lang),
      name: Value(name),
    );
  }

  factory Source.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Source(
      id: serializer.fromJson<int>(json['_id']),
      lang: serializer.fromJson<String>(json['lang']),
      name: serializer.fromJson<String>(json['name']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      '_id': serializer.toJson<int>(id),
      'lang': serializer.toJson<String>(lang),
      'name': serializer.toJson<String>(name),
    };
  }

  Source copyWith({int? id, String? lang, String? name}) => Source(
        id: id ?? this.id,
        lang: lang ?? this.lang,
        name: name ?? this.name,
      );
  Source copyWithCompanion(SourcesCompanion data) {
    return Source(
      id: data.id.present ? data.id.value : this.id,
      lang: data.lang.present ? data.lang.value : this.lang,
      name: data.name.present ? data.name.value : this.name,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Source(')
          ..write('id: $id, ')
          ..write('lang: $lang, ')
          ..write('name: $name')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, lang, name);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Source &&
          other.id == this.id &&
          other.lang == this.lang &&
          other.name == this.name);
}

class SourcesCompanion extends UpdateCompanion<Source> {
  final Value<int> id;
  final Value<String> lang;
  final Value<String> name;
  const SourcesCompanion({
    this.id = const Value.absent(),
    this.lang = const Value.absent(),
    this.name = const Value.absent(),
  });
  SourcesCompanion.insert({
    this.id = const Value.absent(),
    required String lang,
    required String name,
  })  : lang = Value(lang),
        name = Value(name);
  static Insertable<Source> custom({
    Expression<int>? id,
    Expression<String>? lang,
    Expression<String>? name,
  }) {
    return RawValuesInsertable({
      if (id != null) '_id': id,
      if (lang != null) 'lang': lang,
      if (name != null) 'name': name,
    });
  }

  SourcesCompanion copyWith(
      {Value<int>? id, Value<String>? lang, Value<String>? name}) {
    return SourcesCompanion(
      id: id ?? this.id,
      lang: lang ?? this.lang,
      name: name ?? this.name,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['_id'] = Variable<int>(id.value);
    }
    if (lang.present) {
      map['lang'] = Variable<String>(lang.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SourcesCompanion(')
          ..write('id: $id, ')
          ..write('lang: $lang, ')
          ..write('name: $name')
          ..write(')'))
        .toString();
  }
}

class MangaSync extends Table with TableInfo<MangaSync, MangaSyncData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  MangaSync(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      '_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL PRIMARY KEY');
  static const VerificationMeta _mangaIdMeta =
      const VerificationMeta('mangaId');
  late final GeneratedColumn<int> mangaId = GeneratedColumn<int>(
      'manga_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  late final GeneratedColumn<int> syncId = GeneratedColumn<int>(
      'sync_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _remoteIdMeta =
      const VerificationMeta('remoteId');
  late final GeneratedColumn<int> remoteId = GeneratedColumn<int>(
      'remote_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _libraryIdMeta =
      const VerificationMeta('libraryId');
  late final GeneratedColumn<int> libraryId = GeneratedColumn<int>(
      'library_id', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: '');
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _lastChapterReadMeta =
      const VerificationMeta('lastChapterRead');
  late final GeneratedColumn<double> lastChapterRead = GeneratedColumn<double>(
      'last_chapter_read', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _totalChaptersMeta =
      const VerificationMeta('totalChapters');
  late final GeneratedColumn<int> totalChapters = GeneratedColumn<int>(
      'total_chapters', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
      'status', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _scoreMeta = const VerificationMeta('score');
  late final GeneratedColumn<double> score = GeneratedColumn<double>(
      'score', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _remoteUrlMeta =
      const VerificationMeta('remoteUrl');
  late final GeneratedColumn<String> remoteUrl = GeneratedColumn<String>(
      'remote_url', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _startDateMeta =
      const VerificationMeta('startDate');
  late final GeneratedColumn<int> startDate = GeneratedColumn<int>(
      'start_date', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _finishDateMeta =
      const VerificationMeta('finishDate');
  late final GeneratedColumn<int> finishDate = GeneratedColumn<int>(
      'finish_date', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _privateMeta =
      const VerificationMeta('private');
  late final GeneratedColumn<int> private = GeneratedColumn<int>(
      'private', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT 0',
      defaultValue: const CustomExpression('0'));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        mangaId,
        syncId,
        remoteId,
        libraryId,
        title,
        lastChapterRead,
        totalChapters,
        status,
        score,
        remoteUrl,
        startDate,
        finishDate,
        private
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'manga_sync';
  @override
  VerificationContext validateIntegrity(Insertable<MangaSyncData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('_id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['_id']!, _idMeta));
    }
    if (data.containsKey('manga_id')) {
      context.handle(_mangaIdMeta,
          mangaId.isAcceptableOrUnknown(data['manga_id']!, _mangaIdMeta));
    } else if (isInserting) {
      context.missing(_mangaIdMeta);
    }
    if (data.containsKey('sync_id')) {
      context.handle(_syncIdMeta,
          syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta));
    } else if (isInserting) {
      context.missing(_syncIdMeta);
    }
    if (data.containsKey('remote_id')) {
      context.handle(_remoteIdMeta,
          remoteId.isAcceptableOrUnknown(data['remote_id']!, _remoteIdMeta));
    } else if (isInserting) {
      context.missing(_remoteIdMeta);
    }
    if (data.containsKey('library_id')) {
      context.handle(_libraryIdMeta,
          libraryId.isAcceptableOrUnknown(data['library_id']!, _libraryIdMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('last_chapter_read')) {
      context.handle(
          _lastChapterReadMeta,
          lastChapterRead.isAcceptableOrUnknown(
              data['last_chapter_read']!, _lastChapterReadMeta));
    } else if (isInserting) {
      context.missing(_lastChapterReadMeta);
    }
    if (data.containsKey('total_chapters')) {
      context.handle(
          _totalChaptersMeta,
          totalChapters.isAcceptableOrUnknown(
              data['total_chapters']!, _totalChaptersMeta));
    } else if (isInserting) {
      context.missing(_totalChaptersMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('score')) {
      context.handle(
          _scoreMeta, score.isAcceptableOrUnknown(data['score']!, _scoreMeta));
    } else if (isInserting) {
      context.missing(_scoreMeta);
    }
    if (data.containsKey('remote_url')) {
      context.handle(_remoteUrlMeta,
          remoteUrl.isAcceptableOrUnknown(data['remote_url']!, _remoteUrlMeta));
    } else if (isInserting) {
      context.missing(_remoteUrlMeta);
    }
    if (data.containsKey('start_date')) {
      context.handle(_startDateMeta,
          startDate.isAcceptableOrUnknown(data['start_date']!, _startDateMeta));
    } else if (isInserting) {
      context.missing(_startDateMeta);
    }
    if (data.containsKey('finish_date')) {
      context.handle(
          _finishDateMeta,
          finishDate.isAcceptableOrUnknown(
              data['finish_date']!, _finishDateMeta));
    } else if (isInserting) {
      context.missing(_finishDateMeta);
    }
    if (data.containsKey('private')) {
      context.handle(_privateMeta,
          private.isAcceptableOrUnknown(data['private']!, _privateMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {mangaId, syncId},
      ];
  @override
  MangaSyncData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MangaSyncData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}_id'])!,
      mangaId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}manga_id'])!,
      syncId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sync_id'])!,
      remoteId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}remote_id'])!,
      libraryId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}library_id']),
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      lastChapterRead: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}last_chapter_read'])!,
      totalChapters: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}total_chapters'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}status'])!,
      score: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}score'])!,
      remoteUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}remote_url'])!,
      startDate: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}start_date'])!,
      finishDate: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}finish_date'])!,
      private: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}private'])!,
    );
  }

  @override
  MangaSync createAlias(String alias) {
    return MangaSync(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
        'UNIQUE(manga_id, sync_id)ON CONFLICT REPLACE',
        'FOREIGN KEY(manga_id)REFERENCES mangas(_id)ON DELETE CASCADE'
      ];
  @override
  bool get dontWriteConstraints => true;
}

class MangaSyncData extends DataClass implements Insertable<MangaSyncData> {
  final int id;
  final int mangaId;
  final int syncId;
  final int remoteId;
  final int? libraryId;
  final String title;
  final double lastChapterRead;
  final int totalChapters;
  final int status;
  final double score;
  final String remoteUrl;
  final int startDate;
  final int finishDate;
  final int private;
  const MangaSyncData(
      {required this.id,
      required this.mangaId,
      required this.syncId,
      required this.remoteId,
      this.libraryId,
      required this.title,
      required this.lastChapterRead,
      required this.totalChapters,
      required this.status,
      required this.score,
      required this.remoteUrl,
      required this.startDate,
      required this.finishDate,
      required this.private});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['_id'] = Variable<int>(id);
    map['manga_id'] = Variable<int>(mangaId);
    map['sync_id'] = Variable<int>(syncId);
    map['remote_id'] = Variable<int>(remoteId);
    if (!nullToAbsent || libraryId != null) {
      map['library_id'] = Variable<int>(libraryId);
    }
    map['title'] = Variable<String>(title);
    map['last_chapter_read'] = Variable<double>(lastChapterRead);
    map['total_chapters'] = Variable<int>(totalChapters);
    map['status'] = Variable<int>(status);
    map['score'] = Variable<double>(score);
    map['remote_url'] = Variable<String>(remoteUrl);
    map['start_date'] = Variable<int>(startDate);
    map['finish_date'] = Variable<int>(finishDate);
    map['private'] = Variable<int>(private);
    return map;
  }

  MangaSyncCompanion toCompanion(bool nullToAbsent) {
    return MangaSyncCompanion(
      id: Value(id),
      mangaId: Value(mangaId),
      syncId: Value(syncId),
      remoteId: Value(remoteId),
      libraryId: libraryId == null && nullToAbsent
          ? const Value.absent()
          : Value(libraryId),
      title: Value(title),
      lastChapterRead: Value(lastChapterRead),
      totalChapters: Value(totalChapters),
      status: Value(status),
      score: Value(score),
      remoteUrl: Value(remoteUrl),
      startDate: Value(startDate),
      finishDate: Value(finishDate),
      private: Value(private),
    );
  }

  factory MangaSyncData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MangaSyncData(
      id: serializer.fromJson<int>(json['_id']),
      mangaId: serializer.fromJson<int>(json['manga_id']),
      syncId: serializer.fromJson<int>(json['sync_id']),
      remoteId: serializer.fromJson<int>(json['remote_id']),
      libraryId: serializer.fromJson<int?>(json['library_id']),
      title: serializer.fromJson<String>(json['title']),
      lastChapterRead: serializer.fromJson<double>(json['last_chapter_read']),
      totalChapters: serializer.fromJson<int>(json['total_chapters']),
      status: serializer.fromJson<int>(json['status']),
      score: serializer.fromJson<double>(json['score']),
      remoteUrl: serializer.fromJson<String>(json['remote_url']),
      startDate: serializer.fromJson<int>(json['start_date']),
      finishDate: serializer.fromJson<int>(json['finish_date']),
      private: serializer.fromJson<int>(json['private']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      '_id': serializer.toJson<int>(id),
      'manga_id': serializer.toJson<int>(mangaId),
      'sync_id': serializer.toJson<int>(syncId),
      'remote_id': serializer.toJson<int>(remoteId),
      'library_id': serializer.toJson<int?>(libraryId),
      'title': serializer.toJson<String>(title),
      'last_chapter_read': serializer.toJson<double>(lastChapterRead),
      'total_chapters': serializer.toJson<int>(totalChapters),
      'status': serializer.toJson<int>(status),
      'score': serializer.toJson<double>(score),
      'remote_url': serializer.toJson<String>(remoteUrl),
      'start_date': serializer.toJson<int>(startDate),
      'finish_date': serializer.toJson<int>(finishDate),
      'private': serializer.toJson<int>(private),
    };
  }

  MangaSyncData copyWith(
          {int? id,
          int? mangaId,
          int? syncId,
          int? remoteId,
          Value<int?> libraryId = const Value.absent(),
          String? title,
          double? lastChapterRead,
          int? totalChapters,
          int? status,
          double? score,
          String? remoteUrl,
          int? startDate,
          int? finishDate,
          int? private}) =>
      MangaSyncData(
        id: id ?? this.id,
        mangaId: mangaId ?? this.mangaId,
        syncId: syncId ?? this.syncId,
        remoteId: remoteId ?? this.remoteId,
        libraryId: libraryId.present ? libraryId.value : this.libraryId,
        title: title ?? this.title,
        lastChapterRead: lastChapterRead ?? this.lastChapterRead,
        totalChapters: totalChapters ?? this.totalChapters,
        status: status ?? this.status,
        score: score ?? this.score,
        remoteUrl: remoteUrl ?? this.remoteUrl,
        startDate: startDate ?? this.startDate,
        finishDate: finishDate ?? this.finishDate,
        private: private ?? this.private,
      );
  MangaSyncData copyWithCompanion(MangaSyncCompanion data) {
    return MangaSyncData(
      id: data.id.present ? data.id.value : this.id,
      mangaId: data.mangaId.present ? data.mangaId.value : this.mangaId,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      remoteId: data.remoteId.present ? data.remoteId.value : this.remoteId,
      libraryId: data.libraryId.present ? data.libraryId.value : this.libraryId,
      title: data.title.present ? data.title.value : this.title,
      lastChapterRead: data.lastChapterRead.present
          ? data.lastChapterRead.value
          : this.lastChapterRead,
      totalChapters: data.totalChapters.present
          ? data.totalChapters.value
          : this.totalChapters,
      status: data.status.present ? data.status.value : this.status,
      score: data.score.present ? data.score.value : this.score,
      remoteUrl: data.remoteUrl.present ? data.remoteUrl.value : this.remoteUrl,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      finishDate:
          data.finishDate.present ? data.finishDate.value : this.finishDate,
      private: data.private.present ? data.private.value : this.private,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MangaSyncData(')
          ..write('id: $id, ')
          ..write('mangaId: $mangaId, ')
          ..write('syncId: $syncId, ')
          ..write('remoteId: $remoteId, ')
          ..write('libraryId: $libraryId, ')
          ..write('title: $title, ')
          ..write('lastChapterRead: $lastChapterRead, ')
          ..write('totalChapters: $totalChapters, ')
          ..write('status: $status, ')
          ..write('score: $score, ')
          ..write('remoteUrl: $remoteUrl, ')
          ..write('startDate: $startDate, ')
          ..write('finishDate: $finishDate, ')
          ..write('private: $private')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      mangaId,
      syncId,
      remoteId,
      libraryId,
      title,
      lastChapterRead,
      totalChapters,
      status,
      score,
      remoteUrl,
      startDate,
      finishDate,
      private);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MangaSyncData &&
          other.id == this.id &&
          other.mangaId == this.mangaId &&
          other.syncId == this.syncId &&
          other.remoteId == this.remoteId &&
          other.libraryId == this.libraryId &&
          other.title == this.title &&
          other.lastChapterRead == this.lastChapterRead &&
          other.totalChapters == this.totalChapters &&
          other.status == this.status &&
          other.score == this.score &&
          other.remoteUrl == this.remoteUrl &&
          other.startDate == this.startDate &&
          other.finishDate == this.finishDate &&
          other.private == this.private);
}

class MangaSyncCompanion extends UpdateCompanion<MangaSyncData> {
  final Value<int> id;
  final Value<int> mangaId;
  final Value<int> syncId;
  final Value<int> remoteId;
  final Value<int?> libraryId;
  final Value<String> title;
  final Value<double> lastChapterRead;
  final Value<int> totalChapters;
  final Value<int> status;
  final Value<double> score;
  final Value<String> remoteUrl;
  final Value<int> startDate;
  final Value<int> finishDate;
  final Value<int> private;
  const MangaSyncCompanion({
    this.id = const Value.absent(),
    this.mangaId = const Value.absent(),
    this.syncId = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.libraryId = const Value.absent(),
    this.title = const Value.absent(),
    this.lastChapterRead = const Value.absent(),
    this.totalChapters = const Value.absent(),
    this.status = const Value.absent(),
    this.score = const Value.absent(),
    this.remoteUrl = const Value.absent(),
    this.startDate = const Value.absent(),
    this.finishDate = const Value.absent(),
    this.private = const Value.absent(),
  });
  MangaSyncCompanion.insert({
    this.id = const Value.absent(),
    required int mangaId,
    required int syncId,
    required int remoteId,
    this.libraryId = const Value.absent(),
    required String title,
    required double lastChapterRead,
    required int totalChapters,
    required int status,
    required double score,
    required String remoteUrl,
    required int startDate,
    required int finishDate,
    this.private = const Value.absent(),
  })  : mangaId = Value(mangaId),
        syncId = Value(syncId),
        remoteId = Value(remoteId),
        title = Value(title),
        lastChapterRead = Value(lastChapterRead),
        totalChapters = Value(totalChapters),
        status = Value(status),
        score = Value(score),
        remoteUrl = Value(remoteUrl),
        startDate = Value(startDate),
        finishDate = Value(finishDate);
  static Insertable<MangaSyncData> custom({
    Expression<int>? id,
    Expression<int>? mangaId,
    Expression<int>? syncId,
    Expression<int>? remoteId,
    Expression<int>? libraryId,
    Expression<String>? title,
    Expression<double>? lastChapterRead,
    Expression<int>? totalChapters,
    Expression<int>? status,
    Expression<double>? score,
    Expression<String>? remoteUrl,
    Expression<int>? startDate,
    Expression<int>? finishDate,
    Expression<int>? private,
  }) {
    return RawValuesInsertable({
      if (id != null) '_id': id,
      if (mangaId != null) 'manga_id': mangaId,
      if (syncId != null) 'sync_id': syncId,
      if (remoteId != null) 'remote_id': remoteId,
      if (libraryId != null) 'library_id': libraryId,
      if (title != null) 'title': title,
      if (lastChapterRead != null) 'last_chapter_read': lastChapterRead,
      if (totalChapters != null) 'total_chapters': totalChapters,
      if (status != null) 'status': status,
      if (score != null) 'score': score,
      if (remoteUrl != null) 'remote_url': remoteUrl,
      if (startDate != null) 'start_date': startDate,
      if (finishDate != null) 'finish_date': finishDate,
      if (private != null) 'private': private,
    });
  }

  MangaSyncCompanion copyWith(
      {Value<int>? id,
      Value<int>? mangaId,
      Value<int>? syncId,
      Value<int>? remoteId,
      Value<int?>? libraryId,
      Value<String>? title,
      Value<double>? lastChapterRead,
      Value<int>? totalChapters,
      Value<int>? status,
      Value<double>? score,
      Value<String>? remoteUrl,
      Value<int>? startDate,
      Value<int>? finishDate,
      Value<int>? private}) {
    return MangaSyncCompanion(
      id: id ?? this.id,
      mangaId: mangaId ?? this.mangaId,
      syncId: syncId ?? this.syncId,
      remoteId: remoteId ?? this.remoteId,
      libraryId: libraryId ?? this.libraryId,
      title: title ?? this.title,
      lastChapterRead: lastChapterRead ?? this.lastChapterRead,
      totalChapters: totalChapters ?? this.totalChapters,
      status: status ?? this.status,
      score: score ?? this.score,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      startDate: startDate ?? this.startDate,
      finishDate: finishDate ?? this.finishDate,
      private: private ?? this.private,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['_id'] = Variable<int>(id.value);
    }
    if (mangaId.present) {
      map['manga_id'] = Variable<int>(mangaId.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<int>(syncId.value);
    }
    if (remoteId.present) {
      map['remote_id'] = Variable<int>(remoteId.value);
    }
    if (libraryId.present) {
      map['library_id'] = Variable<int>(libraryId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (lastChapterRead.present) {
      map['last_chapter_read'] = Variable<double>(lastChapterRead.value);
    }
    if (totalChapters.present) {
      map['total_chapters'] = Variable<int>(totalChapters.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (score.present) {
      map['score'] = Variable<double>(score.value);
    }
    if (remoteUrl.present) {
      map['remote_url'] = Variable<String>(remoteUrl.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<int>(startDate.value);
    }
    if (finishDate.present) {
      map['finish_date'] = Variable<int>(finishDate.value);
    }
    if (private.present) {
      map['private'] = Variable<int>(private.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MangaSyncCompanion(')
          ..write('id: $id, ')
          ..write('mangaId: $mangaId, ')
          ..write('syncId: $syncId, ')
          ..write('remoteId: $remoteId, ')
          ..write('libraryId: $libraryId, ')
          ..write('title: $title, ')
          ..write('lastChapterRead: $lastChapterRead, ')
          ..write('totalChapters: $totalChapters, ')
          ..write('status: $status, ')
          ..write('score: $score, ')
          ..write('remoteUrl: $remoteUrl, ')
          ..write('startDate: $startDate, ')
          ..write('finishDate: $finishDate, ')
          ..write('private: $private')
          ..write(')'))
        .toString();
  }
}

class Chapters extends Table with TableInfo<Chapters, Chapter> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Chapters(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      '_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL PRIMARY KEY');
  static const VerificationMeta _mangaIdMeta =
      const VerificationMeta('mangaId');
  late final GeneratedColumn<int> mangaId = GeneratedColumn<int>(
      'manga_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
      'url', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _scanlatorMeta =
      const VerificationMeta('scanlator');
  late final GeneratedColumn<String> scanlator = GeneratedColumn<String>(
      'scanlator', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  static const VerificationMeta _readMeta = const VerificationMeta('read');
  late final GeneratedColumn<int> read = GeneratedColumn<int>(
      'read', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _bookmarkMeta =
      const VerificationMeta('bookmark');
  late final GeneratedColumn<int> bookmark = GeneratedColumn<int>(
      'bookmark', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _lastPageReadMeta =
      const VerificationMeta('lastPageRead');
  late final GeneratedColumn<int> lastPageRead = GeneratedColumn<int>(
      'last_page_read', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _chapterNumberMeta =
      const VerificationMeta('chapterNumber');
  late final GeneratedColumn<double> chapterNumber = GeneratedColumn<double>(
      'chapter_number', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _sourceOrderMeta =
      const VerificationMeta('sourceOrder');
  late final GeneratedColumn<int> sourceOrder = GeneratedColumn<int>(
      'source_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _dateFetchMeta =
      const VerificationMeta('dateFetch');
  late final GeneratedColumn<int> dateFetch = GeneratedColumn<int>(
      'date_fetch', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _dateUploadMeta =
      const VerificationMeta('dateUpload');
  late final GeneratedColumn<int> dateUpload = GeneratedColumn<int>(
      'date_upload', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _lastModifiedAtMeta =
      const VerificationMeta('lastModifiedAt');
  late final GeneratedColumn<int> lastModifiedAt = GeneratedColumn<int>(
      'last_modified_at', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT 0',
      defaultValue: const CustomExpression('0'));
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
      'version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT 0',
      defaultValue: const CustomExpression('0'));
  static const VerificationMeta _isSyncingMeta =
      const VerificationMeta('isSyncing');
  late final GeneratedColumn<int> isSyncing = GeneratedColumn<int>(
      'is_syncing', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT 0',
      defaultValue: const CustomExpression('0'));
  static const VerificationMeta _bookmarkNoteMeta =
      const VerificationMeta('bookmarkNote');
  late final GeneratedColumn<String> bookmarkNote = GeneratedColumn<String>(
      'bookmark_note', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: 'DEFAULT NULL',
      defaultValue: const CustomExpression('NULL'));
  static const VerificationMeta _volumeNumberMeta =
      const VerificationMeta('volumeNumber');
  late final GeneratedColumn<double> volumeNumber = GeneratedColumn<double>(
      'volume_number', aliasedName, true,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      $customConstraints: 'DEFAULT NULL',
      defaultValue: const CustomExpression('NULL'));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        mangaId,
        url,
        name,
        scanlator,
        read,
        bookmark,
        lastPageRead,
        chapterNumber,
        sourceOrder,
        dateFetch,
        dateUpload,
        lastModifiedAt,
        version,
        isSyncing,
        bookmarkNote,
        volumeNumber
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chapters';
  @override
  VerificationContext validateIntegrity(Insertable<Chapter> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('_id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['_id']!, _idMeta));
    }
    if (data.containsKey('manga_id')) {
      context.handle(_mangaIdMeta,
          mangaId.isAcceptableOrUnknown(data['manga_id']!, _mangaIdMeta));
    } else if (isInserting) {
      context.missing(_mangaIdMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
          _urlMeta, url.isAcceptableOrUnknown(data['url']!, _urlMeta));
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('scanlator')) {
      context.handle(_scanlatorMeta,
          scanlator.isAcceptableOrUnknown(data['scanlator']!, _scanlatorMeta));
    }
    if (data.containsKey('read')) {
      context.handle(
          _readMeta, read.isAcceptableOrUnknown(data['read']!, _readMeta));
    } else if (isInserting) {
      context.missing(_readMeta);
    }
    if (data.containsKey('bookmark')) {
      context.handle(_bookmarkMeta,
          bookmark.isAcceptableOrUnknown(data['bookmark']!, _bookmarkMeta));
    } else if (isInserting) {
      context.missing(_bookmarkMeta);
    }
    if (data.containsKey('last_page_read')) {
      context.handle(
          _lastPageReadMeta,
          lastPageRead.isAcceptableOrUnknown(
              data['last_page_read']!, _lastPageReadMeta));
    } else if (isInserting) {
      context.missing(_lastPageReadMeta);
    }
    if (data.containsKey('chapter_number')) {
      context.handle(
          _chapterNumberMeta,
          chapterNumber.isAcceptableOrUnknown(
              data['chapter_number']!, _chapterNumberMeta));
    } else if (isInserting) {
      context.missing(_chapterNumberMeta);
    }
    if (data.containsKey('source_order')) {
      context.handle(
          _sourceOrderMeta,
          sourceOrder.isAcceptableOrUnknown(
              data['source_order']!, _sourceOrderMeta));
    } else if (isInserting) {
      context.missing(_sourceOrderMeta);
    }
    if (data.containsKey('date_fetch')) {
      context.handle(_dateFetchMeta,
          dateFetch.isAcceptableOrUnknown(data['date_fetch']!, _dateFetchMeta));
    } else if (isInserting) {
      context.missing(_dateFetchMeta);
    }
    if (data.containsKey('date_upload')) {
      context.handle(
          _dateUploadMeta,
          dateUpload.isAcceptableOrUnknown(
              data['date_upload']!, _dateUploadMeta));
    } else if (isInserting) {
      context.missing(_dateUploadMeta);
    }
    if (data.containsKey('last_modified_at')) {
      context.handle(
          _lastModifiedAtMeta,
          lastModifiedAt.isAcceptableOrUnknown(
              data['last_modified_at']!, _lastModifiedAtMeta));
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    }
    if (data.containsKey('is_syncing')) {
      context.handle(_isSyncingMeta,
          isSyncing.isAcceptableOrUnknown(data['is_syncing']!, _isSyncingMeta));
    }
    if (data.containsKey('bookmark_note')) {
      context.handle(
          _bookmarkNoteMeta,
          bookmarkNote.isAcceptableOrUnknown(
              data['bookmark_note']!, _bookmarkNoteMeta));
    }
    if (data.containsKey('volume_number')) {
      context.handle(
          _volumeNumberMeta,
          volumeNumber.isAcceptableOrUnknown(
              data['volume_number']!, _volumeNumberMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Chapter map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Chapter(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}_id'])!,
      mangaId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}manga_id'])!,
      url: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}url'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      scanlator: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}scanlator']),
      read: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}read'])!,
      bookmark: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}bookmark'])!,
      lastPageRead: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_page_read'])!,
      chapterNumber: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}chapter_number'])!,
      sourceOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}source_order'])!,
      dateFetch: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}date_fetch'])!,
      dateUpload: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}date_upload'])!,
      lastModifiedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_modified_at'])!,
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      isSyncing: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}is_syncing'])!,
      bookmarkNote: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}bookmark_note']),
      volumeNumber: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}volume_number']),
    );
  }

  @override
  Chapters createAlias(String alias) {
    return Chapters(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints =>
      const ['FOREIGN KEY(manga_id)REFERENCES mangas(_id)ON DELETE CASCADE'];
  @override
  bool get dontWriteConstraints => true;
}

class Chapter extends DataClass implements Insertable<Chapter> {
  final int id;
  final int mangaId;
  final String url;
  final String name;
  final String? scanlator;
  final int read;
  final int bookmark;
  final int lastPageRead;
  final double chapterNumber;
  final int sourceOrder;
  final int dateFetch;
  final int dateUpload;
  final int lastModifiedAt;
  final int version;
  final int isSyncing;
  final String? bookmarkNote;
  final double? volumeNumber;
  const Chapter(
      {required this.id,
      required this.mangaId,
      required this.url,
      required this.name,
      this.scanlator,
      required this.read,
      required this.bookmark,
      required this.lastPageRead,
      required this.chapterNumber,
      required this.sourceOrder,
      required this.dateFetch,
      required this.dateUpload,
      required this.lastModifiedAt,
      required this.version,
      required this.isSyncing,
      this.bookmarkNote,
      this.volumeNumber});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['_id'] = Variable<int>(id);
    map['manga_id'] = Variable<int>(mangaId);
    map['url'] = Variable<String>(url);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || scanlator != null) {
      map['scanlator'] = Variable<String>(scanlator);
    }
    map['read'] = Variable<int>(read);
    map['bookmark'] = Variable<int>(bookmark);
    map['last_page_read'] = Variable<int>(lastPageRead);
    map['chapter_number'] = Variable<double>(chapterNumber);
    map['source_order'] = Variable<int>(sourceOrder);
    map['date_fetch'] = Variable<int>(dateFetch);
    map['date_upload'] = Variable<int>(dateUpload);
    map['last_modified_at'] = Variable<int>(lastModifiedAt);
    map['version'] = Variable<int>(version);
    map['is_syncing'] = Variable<int>(isSyncing);
    if (!nullToAbsent || bookmarkNote != null) {
      map['bookmark_note'] = Variable<String>(bookmarkNote);
    }
    if (!nullToAbsent || volumeNumber != null) {
      map['volume_number'] = Variable<double>(volumeNumber);
    }
    return map;
  }

  ChaptersCompanion toCompanion(bool nullToAbsent) {
    return ChaptersCompanion(
      id: Value(id),
      mangaId: Value(mangaId),
      url: Value(url),
      name: Value(name),
      scanlator: scanlator == null && nullToAbsent
          ? const Value.absent()
          : Value(scanlator),
      read: Value(read),
      bookmark: Value(bookmark),
      lastPageRead: Value(lastPageRead),
      chapterNumber: Value(chapterNumber),
      sourceOrder: Value(sourceOrder),
      dateFetch: Value(dateFetch),
      dateUpload: Value(dateUpload),
      lastModifiedAt: Value(lastModifiedAt),
      version: Value(version),
      isSyncing: Value(isSyncing),
      bookmarkNote: bookmarkNote == null && nullToAbsent
          ? const Value.absent()
          : Value(bookmarkNote),
      volumeNumber: volumeNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(volumeNumber),
    );
  }

  factory Chapter.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Chapter(
      id: serializer.fromJson<int>(json['_id']),
      mangaId: serializer.fromJson<int>(json['manga_id']),
      url: serializer.fromJson<String>(json['url']),
      name: serializer.fromJson<String>(json['name']),
      scanlator: serializer.fromJson<String?>(json['scanlator']),
      read: serializer.fromJson<int>(json['read']),
      bookmark: serializer.fromJson<int>(json['bookmark']),
      lastPageRead: serializer.fromJson<int>(json['last_page_read']),
      chapterNumber: serializer.fromJson<double>(json['chapter_number']),
      sourceOrder: serializer.fromJson<int>(json['source_order']),
      dateFetch: serializer.fromJson<int>(json['date_fetch']),
      dateUpload: serializer.fromJson<int>(json['date_upload']),
      lastModifiedAt: serializer.fromJson<int>(json['last_modified_at']),
      version: serializer.fromJson<int>(json['version']),
      isSyncing: serializer.fromJson<int>(json['is_syncing']),
      bookmarkNote: serializer.fromJson<String?>(json['bookmark_note']),
      volumeNumber: serializer.fromJson<double?>(json['volume_number']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      '_id': serializer.toJson<int>(id),
      'manga_id': serializer.toJson<int>(mangaId),
      'url': serializer.toJson<String>(url),
      'name': serializer.toJson<String>(name),
      'scanlator': serializer.toJson<String?>(scanlator),
      'read': serializer.toJson<int>(read),
      'bookmark': serializer.toJson<int>(bookmark),
      'last_page_read': serializer.toJson<int>(lastPageRead),
      'chapter_number': serializer.toJson<double>(chapterNumber),
      'source_order': serializer.toJson<int>(sourceOrder),
      'date_fetch': serializer.toJson<int>(dateFetch),
      'date_upload': serializer.toJson<int>(dateUpload),
      'last_modified_at': serializer.toJson<int>(lastModifiedAt),
      'version': serializer.toJson<int>(version),
      'is_syncing': serializer.toJson<int>(isSyncing),
      'bookmark_note': serializer.toJson<String?>(bookmarkNote),
      'volume_number': serializer.toJson<double?>(volumeNumber),
    };
  }

  Chapter copyWith(
          {int? id,
          int? mangaId,
          String? url,
          String? name,
          Value<String?> scanlator = const Value.absent(),
          int? read,
          int? bookmark,
          int? lastPageRead,
          double? chapterNumber,
          int? sourceOrder,
          int? dateFetch,
          int? dateUpload,
          int? lastModifiedAt,
          int? version,
          int? isSyncing,
          Value<String?> bookmarkNote = const Value.absent(),
          Value<double?> volumeNumber = const Value.absent()}) =>
      Chapter(
        id: id ?? this.id,
        mangaId: mangaId ?? this.mangaId,
        url: url ?? this.url,
        name: name ?? this.name,
        scanlator: scanlator.present ? scanlator.value : this.scanlator,
        read: read ?? this.read,
        bookmark: bookmark ?? this.bookmark,
        lastPageRead: lastPageRead ?? this.lastPageRead,
        chapterNumber: chapterNumber ?? this.chapterNumber,
        sourceOrder: sourceOrder ?? this.sourceOrder,
        dateFetch: dateFetch ?? this.dateFetch,
        dateUpload: dateUpload ?? this.dateUpload,
        lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
        version: version ?? this.version,
        isSyncing: isSyncing ?? this.isSyncing,
        bookmarkNote:
            bookmarkNote.present ? bookmarkNote.value : this.bookmarkNote,
        volumeNumber:
            volumeNumber.present ? volumeNumber.value : this.volumeNumber,
      );
  Chapter copyWithCompanion(ChaptersCompanion data) {
    return Chapter(
      id: data.id.present ? data.id.value : this.id,
      mangaId: data.mangaId.present ? data.mangaId.value : this.mangaId,
      url: data.url.present ? data.url.value : this.url,
      name: data.name.present ? data.name.value : this.name,
      scanlator: data.scanlator.present ? data.scanlator.value : this.scanlator,
      read: data.read.present ? data.read.value : this.read,
      bookmark: data.bookmark.present ? data.bookmark.value : this.bookmark,
      lastPageRead: data.lastPageRead.present
          ? data.lastPageRead.value
          : this.lastPageRead,
      chapterNumber: data.chapterNumber.present
          ? data.chapterNumber.value
          : this.chapterNumber,
      sourceOrder:
          data.sourceOrder.present ? data.sourceOrder.value : this.sourceOrder,
      dateFetch: data.dateFetch.present ? data.dateFetch.value : this.dateFetch,
      dateUpload:
          data.dateUpload.present ? data.dateUpload.value : this.dateUpload,
      lastModifiedAt: data.lastModifiedAt.present
          ? data.lastModifiedAt.value
          : this.lastModifiedAt,
      version: data.version.present ? data.version.value : this.version,
      isSyncing: data.isSyncing.present ? data.isSyncing.value : this.isSyncing,
      bookmarkNote: data.bookmarkNote.present
          ? data.bookmarkNote.value
          : this.bookmarkNote,
      volumeNumber: data.volumeNumber.present
          ? data.volumeNumber.value
          : this.volumeNumber,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Chapter(')
          ..write('id: $id, ')
          ..write('mangaId: $mangaId, ')
          ..write('url: $url, ')
          ..write('name: $name, ')
          ..write('scanlator: $scanlator, ')
          ..write('read: $read, ')
          ..write('bookmark: $bookmark, ')
          ..write('lastPageRead: $lastPageRead, ')
          ..write('chapterNumber: $chapterNumber, ')
          ..write('sourceOrder: $sourceOrder, ')
          ..write('dateFetch: $dateFetch, ')
          ..write('dateUpload: $dateUpload, ')
          ..write('lastModifiedAt: $lastModifiedAt, ')
          ..write('version: $version, ')
          ..write('isSyncing: $isSyncing, ')
          ..write('bookmarkNote: $bookmarkNote, ')
          ..write('volumeNumber: $volumeNumber')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      mangaId,
      url,
      name,
      scanlator,
      read,
      bookmark,
      lastPageRead,
      chapterNumber,
      sourceOrder,
      dateFetch,
      dateUpload,
      lastModifiedAt,
      version,
      isSyncing,
      bookmarkNote,
      volumeNumber);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Chapter &&
          other.id == this.id &&
          other.mangaId == this.mangaId &&
          other.url == this.url &&
          other.name == this.name &&
          other.scanlator == this.scanlator &&
          other.read == this.read &&
          other.bookmark == this.bookmark &&
          other.lastPageRead == this.lastPageRead &&
          other.chapterNumber == this.chapterNumber &&
          other.sourceOrder == this.sourceOrder &&
          other.dateFetch == this.dateFetch &&
          other.dateUpload == this.dateUpload &&
          other.lastModifiedAt == this.lastModifiedAt &&
          other.version == this.version &&
          other.isSyncing == this.isSyncing &&
          other.bookmarkNote == this.bookmarkNote &&
          other.volumeNumber == this.volumeNumber);
}

class ChaptersCompanion extends UpdateCompanion<Chapter> {
  final Value<int> id;
  final Value<int> mangaId;
  final Value<String> url;
  final Value<String> name;
  final Value<String?> scanlator;
  final Value<int> read;
  final Value<int> bookmark;
  final Value<int> lastPageRead;
  final Value<double> chapterNumber;
  final Value<int> sourceOrder;
  final Value<int> dateFetch;
  final Value<int> dateUpload;
  final Value<int> lastModifiedAt;
  final Value<int> version;
  final Value<int> isSyncing;
  final Value<String?> bookmarkNote;
  final Value<double?> volumeNumber;
  const ChaptersCompanion({
    this.id = const Value.absent(),
    this.mangaId = const Value.absent(),
    this.url = const Value.absent(),
    this.name = const Value.absent(),
    this.scanlator = const Value.absent(),
    this.read = const Value.absent(),
    this.bookmark = const Value.absent(),
    this.lastPageRead = const Value.absent(),
    this.chapterNumber = const Value.absent(),
    this.sourceOrder = const Value.absent(),
    this.dateFetch = const Value.absent(),
    this.dateUpload = const Value.absent(),
    this.lastModifiedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.isSyncing = const Value.absent(),
    this.bookmarkNote = const Value.absent(),
    this.volumeNumber = const Value.absent(),
  });
  ChaptersCompanion.insert({
    this.id = const Value.absent(),
    required int mangaId,
    required String url,
    required String name,
    this.scanlator = const Value.absent(),
    required int read,
    required int bookmark,
    required int lastPageRead,
    required double chapterNumber,
    required int sourceOrder,
    required int dateFetch,
    required int dateUpload,
    this.lastModifiedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.isSyncing = const Value.absent(),
    this.bookmarkNote = const Value.absent(),
    this.volumeNumber = const Value.absent(),
  })  : mangaId = Value(mangaId),
        url = Value(url),
        name = Value(name),
        read = Value(read),
        bookmark = Value(bookmark),
        lastPageRead = Value(lastPageRead),
        chapterNumber = Value(chapterNumber),
        sourceOrder = Value(sourceOrder),
        dateFetch = Value(dateFetch),
        dateUpload = Value(dateUpload);
  static Insertable<Chapter> custom({
    Expression<int>? id,
    Expression<int>? mangaId,
    Expression<String>? url,
    Expression<String>? name,
    Expression<String>? scanlator,
    Expression<int>? read,
    Expression<int>? bookmark,
    Expression<int>? lastPageRead,
    Expression<double>? chapterNumber,
    Expression<int>? sourceOrder,
    Expression<int>? dateFetch,
    Expression<int>? dateUpload,
    Expression<int>? lastModifiedAt,
    Expression<int>? version,
    Expression<int>? isSyncing,
    Expression<String>? bookmarkNote,
    Expression<double>? volumeNumber,
  }) {
    return RawValuesInsertable({
      if (id != null) '_id': id,
      if (mangaId != null) 'manga_id': mangaId,
      if (url != null) 'url': url,
      if (name != null) 'name': name,
      if (scanlator != null) 'scanlator': scanlator,
      if (read != null) 'read': read,
      if (bookmark != null) 'bookmark': bookmark,
      if (lastPageRead != null) 'last_page_read': lastPageRead,
      if (chapterNumber != null) 'chapter_number': chapterNumber,
      if (sourceOrder != null) 'source_order': sourceOrder,
      if (dateFetch != null) 'date_fetch': dateFetch,
      if (dateUpload != null) 'date_upload': dateUpload,
      if (lastModifiedAt != null) 'last_modified_at': lastModifiedAt,
      if (version != null) 'version': version,
      if (isSyncing != null) 'is_syncing': isSyncing,
      if (bookmarkNote != null) 'bookmark_note': bookmarkNote,
      if (volumeNumber != null) 'volume_number': volumeNumber,
    });
  }

  ChaptersCompanion copyWith(
      {Value<int>? id,
      Value<int>? mangaId,
      Value<String>? url,
      Value<String>? name,
      Value<String?>? scanlator,
      Value<int>? read,
      Value<int>? bookmark,
      Value<int>? lastPageRead,
      Value<double>? chapterNumber,
      Value<int>? sourceOrder,
      Value<int>? dateFetch,
      Value<int>? dateUpload,
      Value<int>? lastModifiedAt,
      Value<int>? version,
      Value<int>? isSyncing,
      Value<String?>? bookmarkNote,
      Value<double?>? volumeNumber}) {
    return ChaptersCompanion(
      id: id ?? this.id,
      mangaId: mangaId ?? this.mangaId,
      url: url ?? this.url,
      name: name ?? this.name,
      scanlator: scanlator ?? this.scanlator,
      read: read ?? this.read,
      bookmark: bookmark ?? this.bookmark,
      lastPageRead: lastPageRead ?? this.lastPageRead,
      chapterNumber: chapterNumber ?? this.chapterNumber,
      sourceOrder: sourceOrder ?? this.sourceOrder,
      dateFetch: dateFetch ?? this.dateFetch,
      dateUpload: dateUpload ?? this.dateUpload,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      version: version ?? this.version,
      isSyncing: isSyncing ?? this.isSyncing,
      bookmarkNote: bookmarkNote ?? this.bookmarkNote,
      volumeNumber: volumeNumber ?? this.volumeNumber,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['_id'] = Variable<int>(id.value);
    }
    if (mangaId.present) {
      map['manga_id'] = Variable<int>(mangaId.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (scanlator.present) {
      map['scanlator'] = Variable<String>(scanlator.value);
    }
    if (read.present) {
      map['read'] = Variable<int>(read.value);
    }
    if (bookmark.present) {
      map['bookmark'] = Variable<int>(bookmark.value);
    }
    if (lastPageRead.present) {
      map['last_page_read'] = Variable<int>(lastPageRead.value);
    }
    if (chapterNumber.present) {
      map['chapter_number'] = Variable<double>(chapterNumber.value);
    }
    if (sourceOrder.present) {
      map['source_order'] = Variable<int>(sourceOrder.value);
    }
    if (dateFetch.present) {
      map['date_fetch'] = Variable<int>(dateFetch.value);
    }
    if (dateUpload.present) {
      map['date_upload'] = Variable<int>(dateUpload.value);
    }
    if (lastModifiedAt.present) {
      map['last_modified_at'] = Variable<int>(lastModifiedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (isSyncing.present) {
      map['is_syncing'] = Variable<int>(isSyncing.value);
    }
    if (bookmarkNote.present) {
      map['bookmark_note'] = Variable<String>(bookmarkNote.value);
    }
    if (volumeNumber.present) {
      map['volume_number'] = Variable<double>(volumeNumber.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChaptersCompanion(')
          ..write('id: $id, ')
          ..write('mangaId: $mangaId, ')
          ..write('url: $url, ')
          ..write('name: $name, ')
          ..write('scanlator: $scanlator, ')
          ..write('read: $read, ')
          ..write('bookmark: $bookmark, ')
          ..write('lastPageRead: $lastPageRead, ')
          ..write('chapterNumber: $chapterNumber, ')
          ..write('sourceOrder: $sourceOrder, ')
          ..write('dateFetch: $dateFetch, ')
          ..write('dateUpload: $dateUpload, ')
          ..write('lastModifiedAt: $lastModifiedAt, ')
          ..write('version: $version, ')
          ..write('isSyncing: $isSyncing, ')
          ..write('bookmarkNote: $bookmarkNote, ')
          ..write('volumeNumber: $volumeNumber')
          ..write(')'))
        .toString();
  }
}

class History extends Table with TableInfo<History, HistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  History(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      '_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL PRIMARY KEY');
  static const VerificationMeta _chapterIdMeta =
      const VerificationMeta('chapterId');
  late final GeneratedColumn<int> chapterId = GeneratedColumn<int>(
      'chapter_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL UNIQUE');
  static const VerificationMeta _lastReadMeta =
      const VerificationMeta('lastRead');
  late final GeneratedColumn<int> lastRead = GeneratedColumn<int>(
      'last_read', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: '');
  static const VerificationMeta _timeReadMeta =
      const VerificationMeta('timeRead');
  late final GeneratedColumn<int> timeRead = GeneratedColumn<int>(
      'time_read', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  @override
  List<GeneratedColumn> get $columns => [id, chapterId, lastRead, timeRead];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'history';
  @override
  VerificationContext validateIntegrity(Insertable<HistoryData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('_id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['_id']!, _idMeta));
    }
    if (data.containsKey('chapter_id')) {
      context.handle(_chapterIdMeta,
          chapterId.isAcceptableOrUnknown(data['chapter_id']!, _chapterIdMeta));
    } else if (isInserting) {
      context.missing(_chapterIdMeta);
    }
    if (data.containsKey('last_read')) {
      context.handle(_lastReadMeta,
          lastRead.isAcceptableOrUnknown(data['last_read']!, _lastReadMeta));
    }
    if (data.containsKey('time_read')) {
      context.handle(_timeReadMeta,
          timeRead.isAcceptableOrUnknown(data['time_read']!, _timeReadMeta));
    } else if (isInserting) {
      context.missing(_timeReadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HistoryData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}_id'])!,
      chapterId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}chapter_id'])!,
      lastRead: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_read']),
      timeRead: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}time_read'])!,
    );
  }

  @override
  History createAlias(String alias) {
    return History(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
        'FOREIGN KEY(chapter_id)REFERENCES chapters(_id)ON DELETE CASCADE'
      ];
  @override
  bool get dontWriteConstraints => true;
}

class HistoryData extends DataClass implements Insertable<HistoryData> {
  final int id;
  final int chapterId;
  final int? lastRead;
  final int timeRead;
  const HistoryData(
      {required this.id,
      required this.chapterId,
      this.lastRead,
      required this.timeRead});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['_id'] = Variable<int>(id);
    map['chapter_id'] = Variable<int>(chapterId);
    if (!nullToAbsent || lastRead != null) {
      map['last_read'] = Variable<int>(lastRead);
    }
    map['time_read'] = Variable<int>(timeRead);
    return map;
  }

  HistoryCompanion toCompanion(bool nullToAbsent) {
    return HistoryCompanion(
      id: Value(id),
      chapterId: Value(chapterId),
      lastRead: lastRead == null && nullToAbsent
          ? const Value.absent()
          : Value(lastRead),
      timeRead: Value(timeRead),
    );
  }

  factory HistoryData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HistoryData(
      id: serializer.fromJson<int>(json['_id']),
      chapterId: serializer.fromJson<int>(json['chapter_id']),
      lastRead: serializer.fromJson<int?>(json['last_read']),
      timeRead: serializer.fromJson<int>(json['time_read']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      '_id': serializer.toJson<int>(id),
      'chapter_id': serializer.toJson<int>(chapterId),
      'last_read': serializer.toJson<int?>(lastRead),
      'time_read': serializer.toJson<int>(timeRead),
    };
  }

  HistoryData copyWith(
          {int? id,
          int? chapterId,
          Value<int?> lastRead = const Value.absent(),
          int? timeRead}) =>
      HistoryData(
        id: id ?? this.id,
        chapterId: chapterId ?? this.chapterId,
        lastRead: lastRead.present ? lastRead.value : this.lastRead,
        timeRead: timeRead ?? this.timeRead,
      );
  HistoryData copyWithCompanion(HistoryCompanion data) {
    return HistoryData(
      id: data.id.present ? data.id.value : this.id,
      chapterId: data.chapterId.present ? data.chapterId.value : this.chapterId,
      lastRead: data.lastRead.present ? data.lastRead.value : this.lastRead,
      timeRead: data.timeRead.present ? data.timeRead.value : this.timeRead,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HistoryData(')
          ..write('id: $id, ')
          ..write('chapterId: $chapterId, ')
          ..write('lastRead: $lastRead, ')
          ..write('timeRead: $timeRead')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, chapterId, lastRead, timeRead);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistoryData &&
          other.id == this.id &&
          other.chapterId == this.chapterId &&
          other.lastRead == this.lastRead &&
          other.timeRead == this.timeRead);
}

class HistoryCompanion extends UpdateCompanion<HistoryData> {
  final Value<int> id;
  final Value<int> chapterId;
  final Value<int?> lastRead;
  final Value<int> timeRead;
  const HistoryCompanion({
    this.id = const Value.absent(),
    this.chapterId = const Value.absent(),
    this.lastRead = const Value.absent(),
    this.timeRead = const Value.absent(),
  });
  HistoryCompanion.insert({
    this.id = const Value.absent(),
    required int chapterId,
    this.lastRead = const Value.absent(),
    required int timeRead,
  })  : chapterId = Value(chapterId),
        timeRead = Value(timeRead);
  static Insertable<HistoryData> custom({
    Expression<int>? id,
    Expression<int>? chapterId,
    Expression<int>? lastRead,
    Expression<int>? timeRead,
  }) {
    return RawValuesInsertable({
      if (id != null) '_id': id,
      if (chapterId != null) 'chapter_id': chapterId,
      if (lastRead != null) 'last_read': lastRead,
      if (timeRead != null) 'time_read': timeRead,
    });
  }

  HistoryCompanion copyWith(
      {Value<int>? id,
      Value<int>? chapterId,
      Value<int?>? lastRead,
      Value<int>? timeRead}) {
    return HistoryCompanion(
      id: id ?? this.id,
      chapterId: chapterId ?? this.chapterId,
      lastRead: lastRead ?? this.lastRead,
      timeRead: timeRead ?? this.timeRead,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['_id'] = Variable<int>(id.value);
    }
    if (chapterId.present) {
      map['chapter_id'] = Variable<int>(chapterId.value);
    }
    if (lastRead.present) {
      map['last_read'] = Variable<int>(lastRead.value);
    }
    if (timeRead.present) {
      map['time_read'] = Variable<int>(timeRead.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HistoryCompanion(')
          ..write('id: $id, ')
          ..write('chapterId: $chapterId, ')
          ..write('lastRead: $lastRead, ')
          ..write('timeRead: $timeRead')
          ..write(')'))
        .toString();
  }
}

class Categories extends Table with TableInfo<Categories, Category> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Categories(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      '_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL PRIMARY KEY');
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _sortMeta = const VerificationMeta('sort');
  late final GeneratedColumn<int> sort = GeneratedColumn<int>(
      'sort', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _flagsMeta = const VerificationMeta('flags');
  late final GeneratedColumn<int> flags = GeneratedColumn<int>(
      'flags', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _parentIdMeta =
      const VerificationMeta('parentId');
  late final GeneratedColumn<int> parentId = GeneratedColumn<int>(
      'parent_id', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints:
          'DEFAULT NULL REFERENCES categories(_id)ON DELETE SET NULL',
      defaultValue: const CustomExpression('NULL'));
  @override
  List<GeneratedColumn> get $columns => [id, name, sort, flags, parentId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(Insertable<Category> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('_id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['_id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort')) {
      context.handle(
          _sortMeta, sort.isAcceptableOrUnknown(data['sort']!, _sortMeta));
    } else if (isInserting) {
      context.missing(_sortMeta);
    }
    if (data.containsKey('flags')) {
      context.handle(
          _flagsMeta, flags.isAcceptableOrUnknown(data['flags']!, _flagsMeta));
    } else if (isInserting) {
      context.missing(_flagsMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(_parentIdMeta,
          parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Category map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Category(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}_id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      sort: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort'])!,
      flags: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}flags'])!,
      parentId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}parent_id']),
    );
  }

  @override
  Categories createAlias(String alias) {
    return Categories(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class Category extends DataClass implements Insertable<Category> {
  final int id;
  final String name;
  final int sort;
  final int flags;
  final int? parentId;
  const Category(
      {required this.id,
      required this.name,
      required this.sort,
      required this.flags,
      this.parentId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['_id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['sort'] = Variable<int>(sort);
    map['flags'] = Variable<int>(flags);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<int>(parentId);
    }
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      name: Value(name),
      sort: Value(sort),
      flags: Value(flags),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
    );
  }

  factory Category.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Category(
      id: serializer.fromJson<int>(json['_id']),
      name: serializer.fromJson<String>(json['name']),
      sort: serializer.fromJson<int>(json['sort']),
      flags: serializer.fromJson<int>(json['flags']),
      parentId: serializer.fromJson<int?>(json['parent_id']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      '_id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'sort': serializer.toJson<int>(sort),
      'flags': serializer.toJson<int>(flags),
      'parent_id': serializer.toJson<int?>(parentId),
    };
  }

  Category copyWith(
          {int? id,
          String? name,
          int? sort,
          int? flags,
          Value<int?> parentId = const Value.absent()}) =>
      Category(
        id: id ?? this.id,
        name: name ?? this.name,
        sort: sort ?? this.sort,
        flags: flags ?? this.flags,
        parentId: parentId.present ? parentId.value : this.parentId,
      );
  Category copyWithCompanion(CategoriesCompanion data) {
    return Category(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      sort: data.sort.present ? data.sort.value : this.sort,
      flags: data.flags.present ? data.flags.value : this.flags,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Category(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sort: $sort, ')
          ..write('flags: $flags, ')
          ..write('parentId: $parentId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, sort, flags, parentId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.id == this.id &&
          other.name == this.name &&
          other.sort == this.sort &&
          other.flags == this.flags &&
          other.parentId == this.parentId);
}

class CategoriesCompanion extends UpdateCompanion<Category> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> sort;
  final Value<int> flags;
  final Value<int?> parentId;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.sort = const Value.absent(),
    this.flags = const Value.absent(),
    this.parentId = const Value.absent(),
  });
  CategoriesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required int sort,
    required int flags,
    this.parentId = const Value.absent(),
  })  : name = Value(name),
        sort = Value(sort),
        flags = Value(flags);
  static Insertable<Category> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? sort,
    Expression<int>? flags,
    Expression<int>? parentId,
  }) {
    return RawValuesInsertable({
      if (id != null) '_id': id,
      if (name != null) 'name': name,
      if (sort != null) 'sort': sort,
      if (flags != null) 'flags': flags,
      if (parentId != null) 'parent_id': parentId,
    });
  }

  CategoriesCompanion copyWith(
      {Value<int>? id,
      Value<String>? name,
      Value<int>? sort,
      Value<int>? flags,
      Value<int?>? parentId}) {
    return CategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      sort: sort ?? this.sort,
      flags: flags ?? this.flags,
      parentId: parentId ?? this.parentId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['_id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sort.present) {
      map['sort'] = Variable<int>(sort.value);
    }
    if (flags.present) {
      map['flags'] = Variable<int>(flags.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<int>(parentId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sort: $sort, ')
          ..write('flags: $flags, ')
          ..write('parentId: $parentId')
          ..write(')'))
        .toString();
  }
}

class MangasCategories extends Table
    with TableInfo<MangasCategories, MangasCategory> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  MangasCategories(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      '_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL PRIMARY KEY');
  static const VerificationMeta _mangaIdMeta =
      const VerificationMeta('mangaId');
  late final GeneratedColumn<int> mangaId = GeneratedColumn<int>(
      'manga_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _categoryIdMeta =
      const VerificationMeta('categoryId');
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
      'category_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  @override
  List<GeneratedColumn> get $columns => [id, mangaId, categoryId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mangas_categories';
  @override
  VerificationContext validateIntegrity(Insertable<MangasCategory> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('_id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['_id']!, _idMeta));
    }
    if (data.containsKey('manga_id')) {
      context.handle(_mangaIdMeta,
          mangaId.isAcceptableOrUnknown(data['manga_id']!, _mangaIdMeta));
    } else if (isInserting) {
      context.missing(_mangaIdMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
          _categoryIdMeta,
          categoryId.isAcceptableOrUnknown(
              data['category_id']!, _categoryIdMeta));
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MangasCategory map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MangasCategory(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}_id'])!,
      mangaId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}manga_id'])!,
      categoryId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}category_id'])!,
    );
  }

  @override
  MangasCategories createAlias(String alias) {
    return MangasCategories(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
        'FOREIGN KEY(category_id)REFERENCES categories(_id)ON DELETE CASCADE',
        'FOREIGN KEY(manga_id)REFERENCES mangas(_id)ON DELETE CASCADE'
      ];
  @override
  bool get dontWriteConstraints => true;
}

class MangasCategory extends DataClass implements Insertable<MangasCategory> {
  final int id;
  final int mangaId;
  final int categoryId;
  const MangasCategory(
      {required this.id, required this.mangaId, required this.categoryId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['_id'] = Variable<int>(id);
    map['manga_id'] = Variable<int>(mangaId);
    map['category_id'] = Variable<int>(categoryId);
    return map;
  }

  MangasCategoriesCompanion toCompanion(bool nullToAbsent) {
    return MangasCategoriesCompanion(
      id: Value(id),
      mangaId: Value(mangaId),
      categoryId: Value(categoryId),
    );
  }

  factory MangasCategory.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MangasCategory(
      id: serializer.fromJson<int>(json['_id']),
      mangaId: serializer.fromJson<int>(json['manga_id']),
      categoryId: serializer.fromJson<int>(json['category_id']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      '_id': serializer.toJson<int>(id),
      'manga_id': serializer.toJson<int>(mangaId),
      'category_id': serializer.toJson<int>(categoryId),
    };
  }

  MangasCategory copyWith({int? id, int? mangaId, int? categoryId}) =>
      MangasCategory(
        id: id ?? this.id,
        mangaId: mangaId ?? this.mangaId,
        categoryId: categoryId ?? this.categoryId,
      );
  MangasCategory copyWithCompanion(MangasCategoriesCompanion data) {
    return MangasCategory(
      id: data.id.present ? data.id.value : this.id,
      mangaId: data.mangaId.present ? data.mangaId.value : this.mangaId,
      categoryId:
          data.categoryId.present ? data.categoryId.value : this.categoryId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MangasCategory(')
          ..write('id: $id, ')
          ..write('mangaId: $mangaId, ')
          ..write('categoryId: $categoryId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, mangaId, categoryId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MangasCategory &&
          other.id == this.id &&
          other.mangaId == this.mangaId &&
          other.categoryId == this.categoryId);
}

class MangasCategoriesCompanion extends UpdateCompanion<MangasCategory> {
  final Value<int> id;
  final Value<int> mangaId;
  final Value<int> categoryId;
  const MangasCategoriesCompanion({
    this.id = const Value.absent(),
    this.mangaId = const Value.absent(),
    this.categoryId = const Value.absent(),
  });
  MangasCategoriesCompanion.insert({
    this.id = const Value.absent(),
    required int mangaId,
    required int categoryId,
  })  : mangaId = Value(mangaId),
        categoryId = Value(categoryId);
  static Insertable<MangasCategory> custom({
    Expression<int>? id,
    Expression<int>? mangaId,
    Expression<int>? categoryId,
  }) {
    return RawValuesInsertable({
      if (id != null) '_id': id,
      if (mangaId != null) 'manga_id': mangaId,
      if (categoryId != null) 'category_id': categoryId,
    });
  }

  MangasCategoriesCompanion copyWith(
      {Value<int>? id, Value<int>? mangaId, Value<int>? categoryId}) {
    return MangasCategoriesCompanion(
      id: id ?? this.id,
      mangaId: mangaId ?? this.mangaId,
      categoryId: categoryId ?? this.categoryId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['_id'] = Variable<int>(id.value);
    }
    if (mangaId.present) {
      map['manga_id'] = Variable<int>(mangaId.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MangasCategoriesCompanion(')
          ..write('id: $id, ')
          ..write('mangaId: $mangaId, ')
          ..write('categoryId: $categoryId')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final Mangas mangas = Mangas(this);
  late final MangaLinks mangaLinks = MangaLinks(this);
  late final Index mangaLinksPrimaryIndex = Index('manga_links_primary_index',
      'CREATE INDEX IF NOT EXISTS manga_links_primary_index ON manga_links (primary_manga_id)');
  late final Index mangaLinksLinkedIndex = Index('manga_links_linked_index',
      'CREATE INDEX IF NOT EXISTS manga_links_linked_index ON manga_links (linked_manga_id)');
  late final ExtensionRepos extensionRepos = ExtensionRepos(this);
  late final ScanlatorPriority scanlatorPriority = ScanlatorPriority(this);
  late final Index scanlatorPriorityMangaIdIndex = Index(
      'scanlator_priority_manga_id_index',
      'CREATE INDEX scanlator_priority_manga_id_index ON scanlator_priority (manga_id)');
  late final ExcludedScanlators excludedScanlators = ExcludedScanlators(this);
  late final Index excludedScanlatorsMangaIdIndex = Index(
      'excluded_scanlators_manga_id_index',
      'CREATE INDEX excluded_scanlators_manga_id_index ON excluded_scanlators (manga_id)');
  late final Index idxExcludedScanlatorsScanlator = Index(
      'idx_excluded_scanlators_scanlator',
      'CREATE INDEX idx_excluded_scanlators_scanlator ON excluded_scanlators (scanlator)');
  late final Sources sources = Sources(this);
  late final MangaSync mangaSync = MangaSync(this);
  late final Index idxMangaSyncMangaId = Index('idx_manga_sync_manga_id',
      'CREATE INDEX idx_manga_sync_manga_id ON manga_sync (manga_id)');
  late final Chapters chapters = Chapters(this);
  late final History history = History(this);
  late final Index historyHistoryChapterIdIndex = Index(
      'history_history_chapter_id_index',
      'CREATE INDEX history_history_chapter_id_index ON history (chapter_id)');
  late final Index idxHistoryLastRead = Index('idx_history_last_read',
      'CREATE INDEX idx_history_last_read ON history (last_read)');
  late final Categories categories = Categories(this);
  late final MangasCategories mangasCategories = MangasCategories(this);
  late final Index idxMangasCategoriesMangaId = Index(
      'idx_mangas_categories_manga_id',
      'CREATE INDEX idx_mangas_categories_manga_id ON mangas_categories (manga_id)');
  late final Index idxMangasCategoriesCategoryId = Index(
      'idx_mangas_categories_category_id',
      'CREATE INDEX idx_mangas_categories_category_id ON mangas_categories (category_id)');
  late final Trigger insertMangaCategoryUpdateVersion = Trigger(
      'CREATE TRIGGER insert_manga_category_update_version AFTER INSERT ON mangas_categories BEGIN UPDATE mangas SET version = version + 1 WHERE _id = new.manga_id AND (SELECT is_syncing FROM mangas WHERE _id = new.manga_id) = 0;END',
      'insert_manga_category_update_version');
  late final Index categoriesParentIdIndex = Index('categories_parent_id_index',
      'CREATE INDEX IF NOT EXISTS categories_parent_id_index ON categories (parent_id)');
  late final Trigger systemCategoryDeleteTrigger = Trigger(
      'CREATE TRIGGER IF NOT EXISTS system_category_delete_trigger BEFORE DELETE ON categories BEGIN SELECT CASE WHEN old._id <= 0 THEN RAISE (ABORT, \'System category cannot be deleted\') END;END',
      'system_category_delete_trigger');
  late final Index chaptersMangaIdIndex = Index('chapters_manga_id_index',
      'CREATE INDEX chapters_manga_id_index ON chapters (manga_id)');
  late final Index chaptersUnreadByMangaIndex = Index(
      'chapters_unread_by_manga_index',
      'CREATE INDEX chapters_unread_by_manga_index ON chapters (manga_id, read) WHERE read = 0');
  late final Index idxChaptersUrl = Index(
      'idx_chapters_url', 'CREATE INDEX idx_chapters_url ON chapters (url)');
  late final Trigger updateLastModifiedAtChapters = Trigger(
      'CREATE TRIGGER update_last_modified_at_chapters AFTER UPDATE ON chapters BEGIN UPDATE chapters SET last_modified_at = strftime(\'%s\', \'now\') WHERE _id = new._id;END',
      'update_last_modified_at_chapters');
  late final Trigger updateChapterAndMangaVersion = Trigger(
      'CREATE TRIGGER update_chapter_and_manga_version AFTER UPDATE ON chapters WHEN new.is_syncing = 0 AND(new.read != old.read OR new.bookmark != old.bookmark OR new.last_page_read != old.last_page_read)BEGIN UPDATE chapters SET version = version + 1 WHERE _id = new._id;UPDATE mangas SET version = version + 1 WHERE _id = new.manga_id;END',
      'update_chapter_and_manga_version');
  late final Index libraryFavoriteIndex = Index('library_favorite_index',
      'CREATE INDEX library_favorite_index ON mangas (favorite) WHERE favorite = 1');
  late final Index mangasUrlIndex = Index(
      'mangas_url_index', 'CREATE INDEX mangas_url_index ON mangas (url)');
  late final Index idxMangasSource = Index(
      'idx_mangas_source', 'CREATE INDEX idx_mangas_source ON mangas (source)');
  late final Trigger updateLastFavoritedAtMangas = Trigger(
      'CREATE TRIGGER update_last_favorited_at_mangas AFTER UPDATE OF favorite ON mangas BEGIN UPDATE mangas SET favorite_modified_at = strftime(\'%s\', \'now\') WHERE _id = new._id;END',
      'update_last_favorited_at_mangas');
  late final Trigger updateLastModifiedAtMangas = Trigger(
      'CREATE TRIGGER update_last_modified_at_mangas AFTER UPDATE ON mangas BEGIN UPDATE mangas SET last_modified_at = strftime(\'%s\', \'now\') WHERE _id = new._id;END',
      'update_last_modified_at_mangas');
  late final Trigger updateMangaVersion = Trigger(
      'CREATE TRIGGER update_manga_version AFTER UPDATE ON mangas BEGIN UPDATE mangas SET version = version + 1 WHERE _id = new._id AND new.is_syncing = 0 AND(new.url != old.url OR new.description != old.description OR new.favorite != old.favorite);END',
      'update_manga_version');
  Selectable<GetLinksForPrimaryResult> getLinksForPrimary(int primaryId) {
    return customSelect(
        'SELECT linked_manga_id, priority FROM manga_links WHERE primary_manga_id = ?1 ORDER BY priority ASC, linked_manga_id ASC',
        variables: [
          Variable<int>(primaryId)
        ],
        readsFrom: {
          mangaLinks,
        }).map((QueryRow row) => GetLinksForPrimaryResult(
          linkedMangaId: row.read<int>('linked_manga_id'),
          priority: row.read<int>('priority'),
        ));
  }

  Selectable<GetAllLinksForBackupResult> getAllLinksForBackup() {
    return customSelect(
        'SELECT P.source AS primarySource, P.url AS primaryUrl, L.source AS linkedSource, L.url AS linkedUrl, ML.priority AS priority FROM manga_links AS ML JOIN mangas AS P ON P._id = ML.primary_manga_id JOIN mangas AS L ON L._id = ML.linked_manga_id',
        variables: [],
        readsFrom: {
          mangas,
          mangaLinks,
        }).map((QueryRow row) => GetAllLinksForBackupResult(
          primarySource: row.read<int>('primarySource'),
          primaryUrl: row.read<String>('primaryUrl'),
          linkedSource: row.read<int>('linkedSource'),
          linkedUrl: row.read<String>('linkedUrl'),
          priority: row.read<int>('priority'),
        ));
  }

  Selectable<Manga> getLinkedMangas(int primaryId) {
    return customSelect(
        'SELECT M.* FROM mangas AS M JOIN manga_links AS ML ON M._id = ML.linked_manga_id WHERE ML.primary_manga_id = ?1 ORDER BY ML.priority ASC, ML.linked_manga_id ASC',
        variables: [
          Variable<int>(primaryId)
        ],
        readsFrom: {
          mangas,
          mangaLinks,
        }).asyncMap(mangas.mapFromRow);
  }

  Selectable<Manga> getPrimariesOfLinked(int linkedId) {
    return customSelect(
        'SELECT M.* FROM mangas AS M JOIN manga_links AS ML ON M._id = ML.primary_manga_id WHERE ML.linked_manga_id = ?1',
        variables: [
          Variable<int>(linkedId)
        ],
        readsFrom: {
          mangas,
          mangaLinks,
        }).asyncMap(mangas.mapFromRow);
  }

  Selectable<GetAllLinkedWithPrimaryResult> getAllLinkedWithPrimary() {
    return customSelect(
        'SELECT ML.linked_manga_id, M.* FROM manga_links AS ML JOIN mangas AS M ON M._id = ML.primary_manga_id',
        variables: [],
        readsFrom: {
          mangaLinks,
          mangas,
        }).map((QueryRow row) => GetAllLinkedWithPrimaryResult(
          linkedMangaId: row.read<int>('linked_manga_id'),
          id: row.read<int>('_id'),
          source: row.read<int>('source'),
          url: row.read<String>('url'),
          artist: row.readNullable<String>('artist'),
          author: row.readNullable<String>('author'),
          description: row.readNullable<String>('description'),
          genre: row.readNullable<String>('genre'),
          title: row.read<String>('title'),
          status: row.read<int>('status'),
          thumbnailUrl: row.readNullable<String>('thumbnail_url'),
          favorite: row.read<int>('favorite'),
          lastUpdate: row.readNullable<int>('last_update'),
          nextUpdate: row.readNullable<int>('next_update'),
          initialized: row.read<int>('initialized'),
          viewer: row.read<int>('viewer'),
          chapterFlags: row.read<int>('chapter_flags'),
          coverLastModified: row.read<int>('cover_last_modified'),
          dateAdded: row.read<int>('date_added'),
          updateStrategy: row.read<int>('update_strategy'),
          calculateInterval: row.read<int>('calculate_interval'),
          lastModifiedAt: row.read<int>('last_modified_at'),
          favoriteModifiedAt: row.readNullable<int>('favorite_modified_at'),
          version: row.read<int>('version'),
          isSyncing: row.read<int>('is_syncing'),
          notes: row.read<String>('notes'),
        ));
  }

  Future<int> insertLink(int primaryId, int linkedId, int priority) {
    return customInsert(
      'INSERT OR IGNORE INTO manga_links (primary_manga_id, linked_manga_id, priority) VALUES (?1, ?2, ?3)',
      variables: [
        Variable<int>(primaryId),
        Variable<int>(linkedId),
        Variable<int>(priority)
      ],
      updates: {mangaLinks},
    );
  }

  Future<int> deleteLink(int primaryId, int linkedId) {
    return customUpdate(
      'DELETE FROM manga_links WHERE primary_manga_id = ?1 AND linked_manga_id = ?2',
      variables: [Variable<int>(primaryId), Variable<int>(linkedId)],
      updates: {mangaLinks},
      updateKind: UpdateKind.delete,
    );
  }

  Future<int> deleteAllLinksForManga(int mangaId) {
    return customUpdate(
      'DELETE FROM manga_links WHERE primary_manga_id = ?1 OR linked_manga_id = ?1',
      variables: [Variable<int>(mangaId)],
      updates: {mangaLinks},
      updateKind: UpdateKind.delete,
    );
  }

  Future<int> updateLinkPriority(int priority, int primaryId, int linkedId) {
    return customUpdate(
      'UPDATE manga_links SET priority = ?1 WHERE primary_manga_id = ?2 AND linked_manga_id = ?3',
      variables: [
        Variable<int>(priority),
        Variable<int>(primaryId),
        Variable<int>(linkedId)
      ],
      updates: {mangaLinks},
      updateKind: UpdateKind.update,
    );
  }

  Selectable<ExtensionRepo> findRepoByBaseUrl(String baseUrl) {
    return customSelect('SELECT * FROM extension_repos WHERE base_url = ?1',
        variables: [
          Variable<String>(baseUrl)
        ],
        readsFrom: {
          extensionRepos,
        }).asyncMap(extensionRepos.mapFromRow);
  }

  Selectable<ExtensionRepo> findRepoBySigningKeyFingerprint(
      String fingerprint) {
    return customSelect(
        'SELECT * FROM extension_repos WHERE signing_key_fingerprint = ?1',
        variables: [
          Variable<String>(fingerprint)
        ],
        readsFrom: {
          extensionRepos,
        }).asyncMap(extensionRepos.mapFromRow);
  }

  Selectable<ExtensionRepo> findAllRepos() {
    return customSelect('SELECT * FROM extension_repos',
        variables: [],
        readsFrom: {
          extensionRepos,
        }).asyncMap(extensionRepos.mapFromRow);
  }

  Selectable<int> countRepos() {
    return customSelect('SELECT COUNT(*) AS _c0 FROM extension_repos',
        variables: [],
        readsFrom: {
          extensionRepos,
        }).map((QueryRow row) => row.read<int>('_c0'));
  }

  Future<int> insertRepo(String baseUrl, String name, String? shortName,
      String website, String fingerprint) {
    return customInsert(
      'INSERT INTO extension_repos (base_url, name, short_name, website, signing_key_fingerprint) VALUES (?1, ?2, ?3, ?4, ?5)',
      variables: [
        Variable<String>(baseUrl),
        Variable<String>(name),
        Variable<String>(shortName),
        Variable<String>(website),
        Variable<String>(fingerprint)
      ],
      updates: {extensionRepos},
    );
  }

  Future<int> upsertRepo(String baseUrl, String name, String? shortName,
      String website, String fingerprint) {
    return customInsert(
      'INSERT INTO extension_repos (base_url, name, short_name, website, signing_key_fingerprint) VALUES (?1, ?2, ?3, ?4, ?5) ON CONFLICT (base_url) DO UPDATE SET name = ?2, short_name = ?3, website = ?4, signing_key_fingerprint = ?5 WHERE base_url = base_url',
      variables: [
        Variable<String>(baseUrl),
        Variable<String>(name),
        Variable<String>(shortName),
        Variable<String>(website),
        Variable<String>(fingerprint)
      ],
      updates: {extensionRepos},
    );
  }

  Future<int> replaceRepo(String baseUrl, String name, String? shortName,
      String website, String fingerprint) {
    return customInsert(
      'INSERT INTO extension_repos (base_url, name, short_name, website, signing_key_fingerprint) VALUES (?1, ?2, ?3, ?4, ?5) ON CONFLICT (signing_key_fingerprint) DO UPDATE SET base_url = ?1, name = ?2, short_name = ?3, website = ?4 WHERE signing_key_fingerprint = signing_key_fingerprint',
      variables: [
        Variable<String>(baseUrl),
        Variable<String>(name),
        Variable<String>(shortName),
        Variable<String>(website),
        Variable<String>(fingerprint)
      ],
      updates: {extensionRepos},
    );
  }

  Future<int> deleteRepo(String baseUrl) {
    return customUpdate(
      'DELETE FROM extension_repos WHERE base_url = ?1',
      variables: [Variable<String>(baseUrl)],
      updates: {extensionRepos},
      updateKind: UpdateKind.delete,
    );
  }

  Selectable<GetPrioritiesByMangaIdResult> getPrioritiesByMangaId(int mangaId) {
    return customSelect(
        'SELECT scanlator, priority FROM scanlator_priority WHERE manga_id = ?1 ORDER BY priority ASC',
        variables: [
          Variable<int>(mangaId)
        ],
        readsFrom: {
          scanlatorPriority,
        }).map((QueryRow row) => GetPrioritiesByMangaIdResult(
          scanlator: row.read<String>('scanlator'),
          priority: row.read<int>('priority'),
        ));
  }

  Future<int> clearPrioritiesForManga(int mangaId) {
    return customUpdate(
      'DELETE FROM scanlator_priority WHERE manga_id = ?1',
      variables: [Variable<int>(mangaId)],
      updates: {scanlatorPriority},
      updateKind: UpdateKind.delete,
    );
  }

  Future<int> insertScanlatorPriority(
      int mangaId, String scanlator, int priority) {
    return customInsert(
      'INSERT INTO scanlator_priority (manga_id, scanlator, priority) VALUES (?1, ?2, ?3)',
      variables: [
        Variable<int>(mangaId),
        Variable<String>(scanlator),
        Variable<int>(priority)
      ],
      updates: {scanlatorPriority},
    );
  }

  Future<int> insertExcludedScanlator(int mangaId, String scanlator) {
    return customInsert(
      'INSERT INTO excluded_scanlators (manga_id, scanlator) VALUES (?1, ?2)',
      variables: [Variable<int>(mangaId), Variable<String>(scanlator)],
      updates: {excludedScanlators},
    );
  }

  Future<int> removeExcludedScanlators(int mangaId, List<String> scanlators) {
    var $arrayStartIndex = 2;
    final expandedscanlators = $expandVar($arrayStartIndex, scanlators.length);
    $arrayStartIndex += scanlators.length;
    return customUpdate(
      'DELETE FROM excluded_scanlators WHERE manga_id = ?1 AND scanlator IN ($expandedscanlators)',
      variables: [
        Variable<int>(mangaId),
        for (var $ in scanlators) Variable<String>($)
      ],
      updates: {excludedScanlators},
      updateKind: UpdateKind.delete,
    );
  }

  Selectable<String> getExcludedScanlatorsByMangaId(int mangaId) {
    return customSelect(
        'SELECT scanlator FROM excluded_scanlators WHERE manga_id = ?1',
        variables: [
          Variable<int>(mangaId)
        ],
        readsFrom: {
          excludedScanlators,
        }).map((QueryRow row) => row.read<String>('scanlator'));
  }

  Selectable<Source> findAllSources() {
    return customSelect('SELECT * FROM sources', variables: [], readsFrom: {
      sources,
    }).asyncMap(sources.mapFromRow);
  }

  Selectable<Source> findSourceById(int id) {
    return customSelect('SELECT * FROM sources WHERE _id = ?1', variables: [
      Variable<int>(id)
    ], readsFrom: {
      sources,
    }).asyncMap(sources.mapFromRow);
  }

  Future<int> upsertSource(int id, String lang, String name) {
    return customInsert(
      'INSERT INTO sources (_id, lang, name) VALUES (?1, ?2, ?3) ON CONFLICT (_id) DO UPDATE SET lang = ?2, name = ?3 WHERE _id = ?1',
      variables: [
        Variable<int>(id),
        Variable<String>(lang),
        Variable<String>(name)
      ],
      updates: {sources},
    );
  }

  Future<int> deleteMangaSync(int mangaId, int syncId) {
    return customUpdate(
      'DELETE FROM manga_sync WHERE manga_id = ?1 AND sync_id = ?2',
      variables: [Variable<int>(mangaId), Variable<int>(syncId)],
      updates: {mangaSync},
      updateKind: UpdateKind.delete,
    );
  }

  Selectable<MangaSyncData> getTracks() {
    return customSelect('SELECT * FROM manga_sync', variables: [], readsFrom: {
      mangaSync,
    }).asyncMap(mangaSync.mapFromRow);
  }

  Selectable<MangaSyncData> getTrackById(int id) {
    return customSelect('SELECT * FROM manga_sync WHERE _id = ?1', variables: [
      Variable<int>(id)
    ], readsFrom: {
      mangaSync,
    }).asyncMap(mangaSync.mapFromRow);
  }

  Selectable<MangaSyncData> getTracksByMangaId(int mangaId) {
    return customSelect('SELECT * FROM manga_sync WHERE manga_id = ?1',
        variables: [
          Variable<int>(mangaId)
        ],
        readsFrom: {
          mangaSync,
        }).asyncMap(mangaSync.mapFromRow);
  }

  Future<int> insertMangaSync(
      int mangaId,
      int syncId,
      int remoteId,
      int? libraryId,
      String title,
      double lastChapterRead,
      int totalChapters,
      int status,
      double score,
      String remoteUrl,
      int startDate,
      int finishDate,
      int private) {
    return customInsert(
      'INSERT INTO manga_sync (manga_id, sync_id, remote_id, library_id, title, last_chapter_read, total_chapters, status, score, remote_url, start_date, finish_date, private) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)',
      variables: [
        Variable<int>(mangaId),
        Variable<int>(syncId),
        Variable<int>(remoteId),
        Variable<int>(libraryId),
        Variable<String>(title),
        Variable<double>(lastChapterRead),
        Variable<int>(totalChapters),
        Variable<int>(status),
        Variable<double>(score),
        Variable<String>(remoteUrl),
        Variable<int>(startDate),
        Variable<int>(finishDate),
        Variable<int>(private)
      ],
      updates: {mangaSync},
    );
  }

  Future<int> updateMangaSync(
      String mangaId,
      String syncId,
      String mediaId,
      String libraryId,
      String title,
      String lastChapterRead,
      String totalChapter,
      String status,
      String score,
      String trackingUrl,
      String startDate,
      String finishDate,
      String private,
      int id) {
    return customUpdate(
      'UPDATE manga_sync SET manga_id = coalesce(?1, manga_id), sync_id = coalesce(?2, sync_id), remote_id = coalesce(?3, remote_id), library_id = coalesce(?4, library_id), title = coalesce(?5, title), last_chapter_read = coalesce(?6, last_chapter_read), total_chapters = coalesce(?7, total_chapters), status = coalesce(?8, status), score = coalesce(?9, score), remote_url = coalesce(?10, remote_url), start_date = coalesce(?11, start_date), finish_date = coalesce(?12, finish_date), private = coalesce(?13, private) WHERE _id = ?14',
      variables: [
        Variable<String>(mangaId),
        Variable<String>(syncId),
        Variable<String>(mediaId),
        Variable<String>(libraryId),
        Variable<String>(title),
        Variable<String>(lastChapterRead),
        Variable<String>(totalChapter),
        Variable<String>(status),
        Variable<String>(score),
        Variable<String>(trackingUrl),
        Variable<String>(startDate),
        Variable<String>(finishDate),
        Variable<String>(private),
        Variable<int>(id)
      ],
      updates: {mangaSync},
      updateKind: UpdateKind.update,
    );
  }

  Selectable<HistoryData> getHistoryByMangaId(int mangaId) {
    return customSelect(
        'SELECT H._id, H.chapter_id, H.last_read, H.time_read FROM history AS H JOIN chapters AS C ON H.chapter_id = C._id WHERE C.manga_id = ?1 AND C._id = H.chapter_id',
        variables: [
          Variable<int>(mangaId)
        ],
        readsFrom: {
          history,
          chapters,
        }).asyncMap(history.mapFromRow);
  }

  Selectable<HistoryData> getHistoryByChapterUrl(String chapterUrl) {
    return customSelect(
        'SELECT H._id, H.chapter_id, H.last_read, H.time_read FROM history AS H JOIN chapters AS C ON H.chapter_id = C._id WHERE C.url = ?1 AND C._id = H.chapter_id',
        variables: [
          Variable<String>(chapterUrl)
        ],
        readsFrom: {
          history,
          chapters,
        }).asyncMap(history.mapFromRow);
  }

  Future<int> resetHistoryById(int historyId) {
    return customUpdate(
      'UPDATE history SET last_read = 0 WHERE _id = ?1',
      variables: [Variable<int>(historyId)],
      updates: {history},
      updateKind: UpdateKind.update,
    );
  }

  Future<int> resetHistoryByMangaId(int mangaId) {
    return customUpdate(
      'UPDATE history SET last_read = 0 WHERE _id IN (SELECT H._id FROM mangas AS M INNER JOIN chapters AS C ON M._id = C.manga_id INNER JOIN history AS H ON C._id = H.chapter_id WHERE M._id = ?1)',
      variables: [Variable<int>(mangaId)],
      updates: {history},
      updateKind: UpdateKind.update,
    );
  }

  Future<int> removeAllHistory() {
    return customUpdate(
      'DELETE FROM history',
      variables: [],
      updates: {history},
      updateKind: UpdateKind.delete,
    );
  }

  Future<int> removeResettedHistory() {
    return customUpdate(
      'DELETE FROM history WHERE last_read = 0',
      variables: [],
      updates: {history},
      updateKind: UpdateKind.delete,
    );
  }

  Future<int> upsertHistory(int chapterId, int? readAt, int timeRead) {
    return customInsert(
      'INSERT INTO history (chapter_id, last_read, time_read) VALUES (?1, ?2, ?3) ON CONFLICT (chapter_id) DO UPDATE SET last_read = ?2, time_read = time_read + ?3 WHERE chapter_id = ?1',
      variables: [
        Variable<int>(chapterId),
        Variable<int>(readAt),
        Variable<int>(timeRead)
      ],
      updates: {history},
    );
  }

  Selectable<int> getReadDuration() {
    return customSelect(
        'SELECT coalesce(sum(time_read), 0) AS _c0 FROM history',
        variables: [],
        readsFrom: {
          history,
        }).map((QueryRow row) => row.read<int>('_c0'));
  }

  Future<int> insertMangaCategory(int mangaId, int categoryId) {
    return customInsert(
      'INSERT INTO mangas_categories (manga_id, category_id) VALUES (?1, ?2)',
      variables: [Variable<int>(mangaId), Variable<int>(categoryId)],
      updates: {mangasCategories},
    );
  }

  Future<int> deleteMangaCategoryByMangaId(int mangaId) {
    return customUpdate(
      'DELETE FROM mangas_categories WHERE manga_id = ?1',
      variables: [Variable<int>(mangaId)],
      updates: {mangasCategories},
      updateKind: UpdateKind.delete,
    );
  }

  Selectable<Category> getCategory(int id) {
    return customSelect('SELECT * FROM categories WHERE _id = ?1 LIMIT 1',
        variables: [
          Variable<int>(id)
        ],
        readsFrom: {
          categories,
        }).asyncMap(categories.mapFromRow);
  }

  Selectable<Category> getCategories() {
    return customSelect(
        'SELECT _id AS id, name, sort AS categoryOrder, flags, parent_id AS parentId FROM categories ORDER BY sort',
        variables: [],
        readsFrom: {
          categories,
        }).asyncMap(
        (QueryRow row) async => categories.mapFromRowWithAlias(row, const {
              'id': '_id',
              'name': 'name',
              'categoryOrder': 'sort',
              'flags': 'flags',
              'parentId': 'parent_id',
            }));
  }

  Selectable<Category> getCategoriesByMangaId(int mangaId) {
    return customSelect(
        'SELECT C._id AS id, C.name, C.sort AS categoryOrder, C.flags, C.parent_id AS parentId FROM categories AS C JOIN mangas_categories AS MC ON C._id = MC.category_id WHERE MC.manga_id = ?1',
        variables: [
          Variable<int>(mangaId)
        ],
        readsFrom: {
          categories,
          mangasCategories,
        }).asyncMap(
        (QueryRow row) async => categories.mapFromRowWithAlias(row, const {
              'id': '_id',
              'name': 'name',
              'categoryOrder': 'sort',
              'flags': 'flags',
              'parentId': 'parent_id',
            }));
  }

  Future<int> insertCategory(String name, int order, int flags, int? parentId) {
    return customInsert(
      'INSERT INTO categories (name, sort, flags, parent_id) VALUES (?1, ?2, ?3, ?4)',
      variables: [
        Variable<String>(name),
        Variable<int>(order),
        Variable<int>(flags),
        Variable<int>(parentId)
      ],
      updates: {categories},
    );
  }

  Future<int> deleteCategory(int categoryId) {
    return customUpdate(
      'DELETE FROM categories WHERE _id = ?1',
      variables: [Variable<int>(categoryId)],
      updates: {categories},
      updateKind: UpdateKind.delete,
    );
  }

  Future<int> updateCategory(
      String name, String order, String flags, int categoryId) {
    return customUpdate(
      'UPDATE categories SET name = coalesce(?1, name), sort = coalesce(?2, sort), flags = coalesce(?3, flags) WHERE _id = ?4',
      variables: [
        Variable<String>(name),
        Variable<String>(order),
        Variable<String>(flags),
        Variable<int>(categoryId)
      ],
      updates: {categories},
      updateKind: UpdateKind.update,
    );
  }

  Future<int> updateParent(int? parentId, int categoryId) {
    return customUpdate(
      'UPDATE categories SET parent_id = ?1 WHERE _id = ?2',
      variables: [Variable<int>(parentId), Variable<int>(categoryId)],
      updates: {categories},
      updateKind: UpdateKind.update,
    );
  }

  Future<int> updateAllFlags(String var1) {
    return customUpdate(
      'UPDATE categories SET flags = coalesce(?1, flags)',
      variables: [Variable<String>(var1)],
      updates: {categories},
      updateKind: UpdateKind.update,
    );
  }

  Selectable<Chapter> getChaptersByMangaId(int mangaId) {
    return customSelect(
        'SELECT * FROM chapters WHERE manga_id = ?1 ORDER BY source_order',
        variables: [
          Variable<int>(mangaId)
        ],
        readsFrom: {
          chapters,
        }).asyncMap(chapters.mapFromRow);
  }

  Selectable<Manga> getMangaById(int id) {
    return customSelect('SELECT * FROM mangas WHERE _id = ?1', variables: [
      Variable<int>(id)
    ], readsFrom: {
      mangas,
    }).asyncMap(mangas.mapFromRow);
  }

  Selectable<Manga> getMangaByUrlAndSource(String url, int source) {
    return customSelect(
        'SELECT * FROM mangas WHERE url = ?1 AND source = ?2 LIMIT 1',
        variables: [
          Variable<String>(url),
          Variable<int>(source)
        ],
        readsFrom: {
          mangas,
        }).asyncMap(mangas.mapFromRow);
  }

  Selectable<Manga> getFavorites() {
    return customSelect('SELECT * FROM mangas WHERE favorite = 1',
        variables: [],
        readsFrom: {
          mangas,
        }).asyncMap(mangas.mapFromRow);
  }

  Selectable<Manga> getAllManga() {
    return customSelect('SELECT * FROM mangas', variables: [], readsFrom: {
      mangas,
    }).asyncMap(mangas.mapFromRow);
  }

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        mangas,
        mangaLinks,
        mangaLinksPrimaryIndex,
        mangaLinksLinkedIndex,
        extensionRepos,
        scanlatorPriority,
        scanlatorPriorityMangaIdIndex,
        excludedScanlators,
        excludedScanlatorsMangaIdIndex,
        idxExcludedScanlatorsScanlator,
        sources,
        mangaSync,
        idxMangaSyncMangaId,
        chapters,
        history,
        historyHistoryChapterIdIndex,
        idxHistoryLastRead,
        categories,
        mangasCategories,
        idxMangasCategoriesMangaId,
        idxMangasCategoriesCategoryId,
        insertMangaCategoryUpdateVersion,
        categoriesParentIdIndex,
        OnCreateQuery(
            'INSERT OR IGNORE INTO categories (_id, name, sort, flags) VALUES (0, \'\', -1, 0)'),
        systemCategoryDeleteTrigger,
        chaptersMangaIdIndex,
        chaptersUnreadByMangaIndex,
        idxChaptersUrl,
        updateLastModifiedAtChapters,
        updateChapterAndMangaVersion,
        libraryFavoriteIndex,
        mangasUrlIndex,
        idxMangasSource,
        updateLastFavoritedAtMangas,
        updateLastModifiedAtMangas,
        updateMangaVersion
      ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('mangas',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('manga_links', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('mangas',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('manga_links', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('mangas',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('scanlator_priority', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('mangas',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('excluded_scanlators', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('mangas',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('manga_sync', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('mangas',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('chapters', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('chapters',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('history', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('categories',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('mangas_categories', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('mangas',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('mangas_categories', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('mangas_categories',
                limitUpdateKind: UpdateKind.insert),
            result: [
              TableUpdate('mangas', kind: UpdateKind.update),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('categories',
                limitUpdateKind: UpdateKind.delete),
            result: [],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('chapters',
                limitUpdateKind: UpdateKind.update),
            result: [
              TableUpdate('chapters', kind: UpdateKind.update),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('chapters',
                limitUpdateKind: UpdateKind.update),
            result: [
              TableUpdate('chapters', kind: UpdateKind.update),
              TableUpdate('mangas', kind: UpdateKind.update),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('mangas',
                limitUpdateKind: UpdateKind.update),
            result: [
              TableUpdate('mangas', kind: UpdateKind.update),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('mangas',
                limitUpdateKind: UpdateKind.update),
            result: [
              TableUpdate('mangas', kind: UpdateKind.update),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('mangas',
                limitUpdateKind: UpdateKind.update),
            result: [
              TableUpdate('mangas', kind: UpdateKind.update),
            ],
          ),
        ],
      );
}

typedef $MangasCreateCompanionBuilder = MangasCompanion Function({
  Value<int> id,
  required int source,
  required String url,
  Value<String?> artist,
  Value<String?> author,
  Value<String?> description,
  Value<String?> genre,
  required String title,
  required int status,
  Value<String?> thumbnailUrl,
  required int favorite,
  Value<int?> lastUpdate,
  Value<int?> nextUpdate,
  required int initialized,
  required int viewer,
  required int chapterFlags,
  required int coverLastModified,
  required int dateAdded,
  Value<int> updateStrategy,
  Value<int> calculateInterval,
  Value<int> lastModifiedAt,
  Value<int?> favoriteModifiedAt,
  Value<int> version,
  Value<int> isSyncing,
  Value<String> notes,
});
typedef $MangasUpdateCompanionBuilder = MangasCompanion Function({
  Value<int> id,
  Value<int> source,
  Value<String> url,
  Value<String?> artist,
  Value<String?> author,
  Value<String?> description,
  Value<String?> genre,
  Value<String> title,
  Value<int> status,
  Value<String?> thumbnailUrl,
  Value<int> favorite,
  Value<int?> lastUpdate,
  Value<int?> nextUpdate,
  Value<int> initialized,
  Value<int> viewer,
  Value<int> chapterFlags,
  Value<int> coverLastModified,
  Value<int> dateAdded,
  Value<int> updateStrategy,
  Value<int> calculateInterval,
  Value<int> lastModifiedAt,
  Value<int?> favoriteModifiedAt,
  Value<int> version,
  Value<int> isSyncing,
  Value<String> notes,
});

class $MangasFilterComposer extends Composer<_$AppDatabase, Mangas> {
  $MangasFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get url => $composableBuilder(
      column: $table.url, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get artist => $composableBuilder(
      column: $table.artist, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get author => $composableBuilder(
      column: $table.author, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get genre => $composableBuilder(
      column: $table.genre, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get thumbnailUrl => $composableBuilder(
      column: $table.thumbnailUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get favorite => $composableBuilder(
      column: $table.favorite, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastUpdate => $composableBuilder(
      column: $table.lastUpdate, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get nextUpdate => $composableBuilder(
      column: $table.nextUpdate, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get initialized => $composableBuilder(
      column: $table.initialized, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get viewer => $composableBuilder(
      column: $table.viewer, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get chapterFlags => $composableBuilder(
      column: $table.chapterFlags, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get coverLastModified => $composableBuilder(
      column: $table.coverLastModified,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get dateAdded => $composableBuilder(
      column: $table.dateAdded, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updateStrategy => $composableBuilder(
      column: $table.updateStrategy,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get calculateInterval => $composableBuilder(
      column: $table.calculateInterval,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastModifiedAt => $composableBuilder(
      column: $table.lastModifiedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get favoriteModifiedAt => $composableBuilder(
      column: $table.favoriteModifiedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get isSyncing => $composableBuilder(
      column: $table.isSyncing, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnFilters(column));
}

class $MangasOrderingComposer extends Composer<_$AppDatabase, Mangas> {
  $MangasOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get url => $composableBuilder(
      column: $table.url, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get artist => $composableBuilder(
      column: $table.artist, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get author => $composableBuilder(
      column: $table.author, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get genre => $composableBuilder(
      column: $table.genre, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get thumbnailUrl => $composableBuilder(
      column: $table.thumbnailUrl,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get favorite => $composableBuilder(
      column: $table.favorite, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastUpdate => $composableBuilder(
      column: $table.lastUpdate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get nextUpdate => $composableBuilder(
      column: $table.nextUpdate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get initialized => $composableBuilder(
      column: $table.initialized, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get viewer => $composableBuilder(
      column: $table.viewer, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get chapterFlags => $composableBuilder(
      column: $table.chapterFlags,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get coverLastModified => $composableBuilder(
      column: $table.coverLastModified,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get dateAdded => $composableBuilder(
      column: $table.dateAdded, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updateStrategy => $composableBuilder(
      column: $table.updateStrategy,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get calculateInterval => $composableBuilder(
      column: $table.calculateInterval,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastModifiedAt => $composableBuilder(
      column: $table.lastModifiedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get favoriteModifiedAt => $composableBuilder(
      column: $table.favoriteModifiedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get isSyncing => $composableBuilder(
      column: $table.isSyncing, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnOrderings(column));
}

class $MangasAnnotationComposer extends Composer<_$AppDatabase, Mangas> {
  $MangasAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get genre =>
      $composableBuilder(column: $table.genre, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get thumbnailUrl => $composableBuilder(
      column: $table.thumbnailUrl, builder: (column) => column);

  GeneratedColumn<int> get favorite =>
      $composableBuilder(column: $table.favorite, builder: (column) => column);

  GeneratedColumn<int> get lastUpdate => $composableBuilder(
      column: $table.lastUpdate, builder: (column) => column);

  GeneratedColumn<int> get nextUpdate => $composableBuilder(
      column: $table.nextUpdate, builder: (column) => column);

  GeneratedColumn<int> get initialized => $composableBuilder(
      column: $table.initialized, builder: (column) => column);

  GeneratedColumn<int> get viewer =>
      $composableBuilder(column: $table.viewer, builder: (column) => column);

  GeneratedColumn<int> get chapterFlags => $composableBuilder(
      column: $table.chapterFlags, builder: (column) => column);

  GeneratedColumn<int> get coverLastModified => $composableBuilder(
      column: $table.coverLastModified, builder: (column) => column);

  GeneratedColumn<int> get dateAdded =>
      $composableBuilder(column: $table.dateAdded, builder: (column) => column);

  GeneratedColumn<int> get updateStrategy => $composableBuilder(
      column: $table.updateStrategy, builder: (column) => column);

  GeneratedColumn<int> get calculateInterval => $composableBuilder(
      column: $table.calculateInterval, builder: (column) => column);

  GeneratedColumn<int> get lastModifiedAt => $composableBuilder(
      column: $table.lastModifiedAt, builder: (column) => column);

  GeneratedColumn<int> get favoriteModifiedAt => $composableBuilder(
      column: $table.favoriteModifiedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<int> get isSyncing =>
      $composableBuilder(column: $table.isSyncing, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);
}

class $MangasTableManager extends RootTableManager<
    _$AppDatabase,
    Mangas,
    Manga,
    $MangasFilterComposer,
    $MangasOrderingComposer,
    $MangasAnnotationComposer,
    $MangasCreateCompanionBuilder,
    $MangasUpdateCompanionBuilder,
    (Manga, BaseReferences<_$AppDatabase, Mangas, Manga>),
    Manga,
    PrefetchHooks Function()> {
  $MangasTableManager(_$AppDatabase db, Mangas table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $MangasFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $MangasOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $MangasAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> source = const Value.absent(),
            Value<String> url = const Value.absent(),
            Value<String?> artist = const Value.absent(),
            Value<String?> author = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String?> genre = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<int> status = const Value.absent(),
            Value<String?> thumbnailUrl = const Value.absent(),
            Value<int> favorite = const Value.absent(),
            Value<int?> lastUpdate = const Value.absent(),
            Value<int?> nextUpdate = const Value.absent(),
            Value<int> initialized = const Value.absent(),
            Value<int> viewer = const Value.absent(),
            Value<int> chapterFlags = const Value.absent(),
            Value<int> coverLastModified = const Value.absent(),
            Value<int> dateAdded = const Value.absent(),
            Value<int> updateStrategy = const Value.absent(),
            Value<int> calculateInterval = const Value.absent(),
            Value<int> lastModifiedAt = const Value.absent(),
            Value<int?> favoriteModifiedAt = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<int> isSyncing = const Value.absent(),
            Value<String> notes = const Value.absent(),
          }) =>
              MangasCompanion(
            id: id,
            source: source,
            url: url,
            artist: artist,
            author: author,
            description: description,
            genre: genre,
            title: title,
            status: status,
            thumbnailUrl: thumbnailUrl,
            favorite: favorite,
            lastUpdate: lastUpdate,
            nextUpdate: nextUpdate,
            initialized: initialized,
            viewer: viewer,
            chapterFlags: chapterFlags,
            coverLastModified: coverLastModified,
            dateAdded: dateAdded,
            updateStrategy: updateStrategy,
            calculateInterval: calculateInterval,
            lastModifiedAt: lastModifiedAt,
            favoriteModifiedAt: favoriteModifiedAt,
            version: version,
            isSyncing: isSyncing,
            notes: notes,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int source,
            required String url,
            Value<String?> artist = const Value.absent(),
            Value<String?> author = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String?> genre = const Value.absent(),
            required String title,
            required int status,
            Value<String?> thumbnailUrl = const Value.absent(),
            required int favorite,
            Value<int?> lastUpdate = const Value.absent(),
            Value<int?> nextUpdate = const Value.absent(),
            required int initialized,
            required int viewer,
            required int chapterFlags,
            required int coverLastModified,
            required int dateAdded,
            Value<int> updateStrategy = const Value.absent(),
            Value<int> calculateInterval = const Value.absent(),
            Value<int> lastModifiedAt = const Value.absent(),
            Value<int?> favoriteModifiedAt = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<int> isSyncing = const Value.absent(),
            Value<String> notes = const Value.absent(),
          }) =>
              MangasCompanion.insert(
            id: id,
            source: source,
            url: url,
            artist: artist,
            author: author,
            description: description,
            genre: genre,
            title: title,
            status: status,
            thumbnailUrl: thumbnailUrl,
            favorite: favorite,
            lastUpdate: lastUpdate,
            nextUpdate: nextUpdate,
            initialized: initialized,
            viewer: viewer,
            chapterFlags: chapterFlags,
            coverLastModified: coverLastModified,
            dateAdded: dateAdded,
            updateStrategy: updateStrategy,
            calculateInterval: calculateInterval,
            lastModifiedAt: lastModifiedAt,
            favoriteModifiedAt: favoriteModifiedAt,
            version: version,
            isSyncing: isSyncing,
            notes: notes,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $MangasProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    Mangas,
    Manga,
    $MangasFilterComposer,
    $MangasOrderingComposer,
    $MangasAnnotationComposer,
    $MangasCreateCompanionBuilder,
    $MangasUpdateCompanionBuilder,
    (Manga, BaseReferences<_$AppDatabase, Mangas, Manga>),
    Manga,
    PrefetchHooks Function()>;
typedef $MangaLinksCreateCompanionBuilder = MangaLinksCompanion Function({
  required int primaryMangaId,
  required int linkedMangaId,
  Value<int> priority,
  Value<int> rowid,
});
typedef $MangaLinksUpdateCompanionBuilder = MangaLinksCompanion Function({
  Value<int> primaryMangaId,
  Value<int> linkedMangaId,
  Value<int> priority,
  Value<int> rowid,
});

class $MangaLinksFilterComposer extends Composer<_$AppDatabase, MangaLinks> {
  $MangaLinksFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get primaryMangaId => $composableBuilder(
      column: $table.primaryMangaId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get linkedMangaId => $composableBuilder(
      column: $table.linkedMangaId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get priority => $composableBuilder(
      column: $table.priority, builder: (column) => ColumnFilters(column));
}

class $MangaLinksOrderingComposer extends Composer<_$AppDatabase, MangaLinks> {
  $MangaLinksOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get primaryMangaId => $composableBuilder(
      column: $table.primaryMangaId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get linkedMangaId => $composableBuilder(
      column: $table.linkedMangaId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get priority => $composableBuilder(
      column: $table.priority, builder: (column) => ColumnOrderings(column));
}

class $MangaLinksAnnotationComposer
    extends Composer<_$AppDatabase, MangaLinks> {
  $MangaLinksAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get primaryMangaId => $composableBuilder(
      column: $table.primaryMangaId, builder: (column) => column);

  GeneratedColumn<int> get linkedMangaId => $composableBuilder(
      column: $table.linkedMangaId, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);
}

class $MangaLinksTableManager extends RootTableManager<
    _$AppDatabase,
    MangaLinks,
    MangaLink,
    $MangaLinksFilterComposer,
    $MangaLinksOrderingComposer,
    $MangaLinksAnnotationComposer,
    $MangaLinksCreateCompanionBuilder,
    $MangaLinksUpdateCompanionBuilder,
    (MangaLink, BaseReferences<_$AppDatabase, MangaLinks, MangaLink>),
    MangaLink,
    PrefetchHooks Function()> {
  $MangaLinksTableManager(_$AppDatabase db, MangaLinks table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $MangaLinksFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $MangaLinksOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $MangaLinksAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> primaryMangaId = const Value.absent(),
            Value<int> linkedMangaId = const Value.absent(),
            Value<int> priority = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MangaLinksCompanion(
            primaryMangaId: primaryMangaId,
            linkedMangaId: linkedMangaId,
            priority: priority,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required int primaryMangaId,
            required int linkedMangaId,
            Value<int> priority = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MangaLinksCompanion.insert(
            primaryMangaId: primaryMangaId,
            linkedMangaId: linkedMangaId,
            priority: priority,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $MangaLinksProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    MangaLinks,
    MangaLink,
    $MangaLinksFilterComposer,
    $MangaLinksOrderingComposer,
    $MangaLinksAnnotationComposer,
    $MangaLinksCreateCompanionBuilder,
    $MangaLinksUpdateCompanionBuilder,
    (MangaLink, BaseReferences<_$AppDatabase, MangaLinks, MangaLink>),
    MangaLink,
    PrefetchHooks Function()>;
typedef $ExtensionReposCreateCompanionBuilder = ExtensionReposCompanion
    Function({
  required String baseUrl,
  required String name,
  Value<String?> shortName,
  required String website,
  required String signingKeyFingerprint,
  Value<int> rowid,
});
typedef $ExtensionReposUpdateCompanionBuilder = ExtensionReposCompanion
    Function({
  Value<String> baseUrl,
  Value<String> name,
  Value<String?> shortName,
  Value<String> website,
  Value<String> signingKeyFingerprint,
  Value<int> rowid,
});

class $ExtensionReposFilterComposer
    extends Composer<_$AppDatabase, ExtensionRepos> {
  $ExtensionReposFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get baseUrl => $composableBuilder(
      column: $table.baseUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get shortName => $composableBuilder(
      column: $table.shortName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get website => $composableBuilder(
      column: $table.website, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get signingKeyFingerprint => $composableBuilder(
      column: $table.signingKeyFingerprint,
      builder: (column) => ColumnFilters(column));
}

class $ExtensionReposOrderingComposer
    extends Composer<_$AppDatabase, ExtensionRepos> {
  $ExtensionReposOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get baseUrl => $composableBuilder(
      column: $table.baseUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get shortName => $composableBuilder(
      column: $table.shortName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get website => $composableBuilder(
      column: $table.website, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get signingKeyFingerprint => $composableBuilder(
      column: $table.signingKeyFingerprint,
      builder: (column) => ColumnOrderings(column));
}

class $ExtensionReposAnnotationComposer
    extends Composer<_$AppDatabase, ExtensionRepos> {
  $ExtensionReposAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get baseUrl =>
      $composableBuilder(column: $table.baseUrl, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get shortName =>
      $composableBuilder(column: $table.shortName, builder: (column) => column);

  GeneratedColumn<String> get website =>
      $composableBuilder(column: $table.website, builder: (column) => column);

  GeneratedColumn<String> get signingKeyFingerprint => $composableBuilder(
      column: $table.signingKeyFingerprint, builder: (column) => column);
}

class $ExtensionReposTableManager extends RootTableManager<
    _$AppDatabase,
    ExtensionRepos,
    ExtensionRepo,
    $ExtensionReposFilterComposer,
    $ExtensionReposOrderingComposer,
    $ExtensionReposAnnotationComposer,
    $ExtensionReposCreateCompanionBuilder,
    $ExtensionReposUpdateCompanionBuilder,
    (
      ExtensionRepo,
      BaseReferences<_$AppDatabase, ExtensionRepos, ExtensionRepo>
    ),
    ExtensionRepo,
    PrefetchHooks Function()> {
  $ExtensionReposTableManager(_$AppDatabase db, ExtensionRepos table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ExtensionReposFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ExtensionReposOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ExtensionReposAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> baseUrl = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> shortName = const Value.absent(),
            Value<String> website = const Value.absent(),
            Value<String> signingKeyFingerprint = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ExtensionReposCompanion(
            baseUrl: baseUrl,
            name: name,
            shortName: shortName,
            website: website,
            signingKeyFingerprint: signingKeyFingerprint,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String baseUrl,
            required String name,
            Value<String?> shortName = const Value.absent(),
            required String website,
            required String signingKeyFingerprint,
            Value<int> rowid = const Value.absent(),
          }) =>
              ExtensionReposCompanion.insert(
            baseUrl: baseUrl,
            name: name,
            shortName: shortName,
            website: website,
            signingKeyFingerprint: signingKeyFingerprint,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $ExtensionReposProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    ExtensionRepos,
    ExtensionRepo,
    $ExtensionReposFilterComposer,
    $ExtensionReposOrderingComposer,
    $ExtensionReposAnnotationComposer,
    $ExtensionReposCreateCompanionBuilder,
    $ExtensionReposUpdateCompanionBuilder,
    (
      ExtensionRepo,
      BaseReferences<_$AppDatabase, ExtensionRepos, ExtensionRepo>
    ),
    ExtensionRepo,
    PrefetchHooks Function()>;
typedef $ScanlatorPriorityCreateCompanionBuilder = ScanlatorPriorityCompanion
    Function({
  required int mangaId,
  required String scanlator,
  required int priority,
  Value<int> rowid,
});
typedef $ScanlatorPriorityUpdateCompanionBuilder = ScanlatorPriorityCompanion
    Function({
  Value<int> mangaId,
  Value<String> scanlator,
  Value<int> priority,
  Value<int> rowid,
});

class $ScanlatorPriorityFilterComposer
    extends Composer<_$AppDatabase, ScanlatorPriority> {
  $ScanlatorPriorityFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get mangaId => $composableBuilder(
      column: $table.mangaId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get scanlator => $composableBuilder(
      column: $table.scanlator, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get priority => $composableBuilder(
      column: $table.priority, builder: (column) => ColumnFilters(column));
}

class $ScanlatorPriorityOrderingComposer
    extends Composer<_$AppDatabase, ScanlatorPriority> {
  $ScanlatorPriorityOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get mangaId => $composableBuilder(
      column: $table.mangaId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get scanlator => $composableBuilder(
      column: $table.scanlator, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get priority => $composableBuilder(
      column: $table.priority, builder: (column) => ColumnOrderings(column));
}

class $ScanlatorPriorityAnnotationComposer
    extends Composer<_$AppDatabase, ScanlatorPriority> {
  $ScanlatorPriorityAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get mangaId =>
      $composableBuilder(column: $table.mangaId, builder: (column) => column);

  GeneratedColumn<String> get scanlator =>
      $composableBuilder(column: $table.scanlator, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);
}

class $ScanlatorPriorityTableManager extends RootTableManager<
    _$AppDatabase,
    ScanlatorPriority,
    ScanlatorPriorityData,
    $ScanlatorPriorityFilterComposer,
    $ScanlatorPriorityOrderingComposer,
    $ScanlatorPriorityAnnotationComposer,
    $ScanlatorPriorityCreateCompanionBuilder,
    $ScanlatorPriorityUpdateCompanionBuilder,
    (
      ScanlatorPriorityData,
      BaseReferences<_$AppDatabase, ScanlatorPriority, ScanlatorPriorityData>
    ),
    ScanlatorPriorityData,
    PrefetchHooks Function()> {
  $ScanlatorPriorityTableManager(_$AppDatabase db, ScanlatorPriority table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ScanlatorPriorityFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ScanlatorPriorityOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ScanlatorPriorityAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> mangaId = const Value.absent(),
            Value<String> scanlator = const Value.absent(),
            Value<int> priority = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ScanlatorPriorityCompanion(
            mangaId: mangaId,
            scanlator: scanlator,
            priority: priority,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required int mangaId,
            required String scanlator,
            required int priority,
            Value<int> rowid = const Value.absent(),
          }) =>
              ScanlatorPriorityCompanion.insert(
            mangaId: mangaId,
            scanlator: scanlator,
            priority: priority,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $ScanlatorPriorityProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    ScanlatorPriority,
    ScanlatorPriorityData,
    $ScanlatorPriorityFilterComposer,
    $ScanlatorPriorityOrderingComposer,
    $ScanlatorPriorityAnnotationComposer,
    $ScanlatorPriorityCreateCompanionBuilder,
    $ScanlatorPriorityUpdateCompanionBuilder,
    (
      ScanlatorPriorityData,
      BaseReferences<_$AppDatabase, ScanlatorPriority, ScanlatorPriorityData>
    ),
    ScanlatorPriorityData,
    PrefetchHooks Function()>;
typedef $ExcludedScanlatorsCreateCompanionBuilder = ExcludedScanlatorsCompanion
    Function({
  required int mangaId,
  required String scanlator,
  Value<int> rowid,
});
typedef $ExcludedScanlatorsUpdateCompanionBuilder = ExcludedScanlatorsCompanion
    Function({
  Value<int> mangaId,
  Value<String> scanlator,
  Value<int> rowid,
});

class $ExcludedScanlatorsFilterComposer
    extends Composer<_$AppDatabase, ExcludedScanlators> {
  $ExcludedScanlatorsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get mangaId => $composableBuilder(
      column: $table.mangaId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get scanlator => $composableBuilder(
      column: $table.scanlator, builder: (column) => ColumnFilters(column));
}

class $ExcludedScanlatorsOrderingComposer
    extends Composer<_$AppDatabase, ExcludedScanlators> {
  $ExcludedScanlatorsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get mangaId => $composableBuilder(
      column: $table.mangaId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get scanlator => $composableBuilder(
      column: $table.scanlator, builder: (column) => ColumnOrderings(column));
}

class $ExcludedScanlatorsAnnotationComposer
    extends Composer<_$AppDatabase, ExcludedScanlators> {
  $ExcludedScanlatorsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get mangaId =>
      $composableBuilder(column: $table.mangaId, builder: (column) => column);

  GeneratedColumn<String> get scanlator =>
      $composableBuilder(column: $table.scanlator, builder: (column) => column);
}

class $ExcludedScanlatorsTableManager extends RootTableManager<
    _$AppDatabase,
    ExcludedScanlators,
    ExcludedScanlator,
    $ExcludedScanlatorsFilterComposer,
    $ExcludedScanlatorsOrderingComposer,
    $ExcludedScanlatorsAnnotationComposer,
    $ExcludedScanlatorsCreateCompanionBuilder,
    $ExcludedScanlatorsUpdateCompanionBuilder,
    (
      ExcludedScanlator,
      BaseReferences<_$AppDatabase, ExcludedScanlators, ExcludedScanlator>
    ),
    ExcludedScanlator,
    PrefetchHooks Function()> {
  $ExcludedScanlatorsTableManager(_$AppDatabase db, ExcludedScanlators table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ExcludedScanlatorsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ExcludedScanlatorsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ExcludedScanlatorsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> mangaId = const Value.absent(),
            Value<String> scanlator = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ExcludedScanlatorsCompanion(
            mangaId: mangaId,
            scanlator: scanlator,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required int mangaId,
            required String scanlator,
            Value<int> rowid = const Value.absent(),
          }) =>
              ExcludedScanlatorsCompanion.insert(
            mangaId: mangaId,
            scanlator: scanlator,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $ExcludedScanlatorsProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    ExcludedScanlators,
    ExcludedScanlator,
    $ExcludedScanlatorsFilterComposer,
    $ExcludedScanlatorsOrderingComposer,
    $ExcludedScanlatorsAnnotationComposer,
    $ExcludedScanlatorsCreateCompanionBuilder,
    $ExcludedScanlatorsUpdateCompanionBuilder,
    (
      ExcludedScanlator,
      BaseReferences<_$AppDatabase, ExcludedScanlators, ExcludedScanlator>
    ),
    ExcludedScanlator,
    PrefetchHooks Function()>;
typedef $SourcesCreateCompanionBuilder = SourcesCompanion Function({
  Value<int> id,
  required String lang,
  required String name,
});
typedef $SourcesUpdateCompanionBuilder = SourcesCompanion Function({
  Value<int> id,
  Value<String> lang,
  Value<String> name,
});

class $SourcesFilterComposer extends Composer<_$AppDatabase, Sources> {
  $SourcesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lang => $composableBuilder(
      column: $table.lang, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));
}

class $SourcesOrderingComposer extends Composer<_$AppDatabase, Sources> {
  $SourcesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lang => $composableBuilder(
      column: $table.lang, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));
}

class $SourcesAnnotationComposer extends Composer<_$AppDatabase, Sources> {
  $SourcesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get lang =>
      $composableBuilder(column: $table.lang, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);
}

class $SourcesTableManager extends RootTableManager<
    _$AppDatabase,
    Sources,
    Source,
    $SourcesFilterComposer,
    $SourcesOrderingComposer,
    $SourcesAnnotationComposer,
    $SourcesCreateCompanionBuilder,
    $SourcesUpdateCompanionBuilder,
    (Source, BaseReferences<_$AppDatabase, Sources, Source>),
    Source,
    PrefetchHooks Function()> {
  $SourcesTableManager(_$AppDatabase db, Sources table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $SourcesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $SourcesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $SourcesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> lang = const Value.absent(),
            Value<String> name = const Value.absent(),
          }) =>
              SourcesCompanion(
            id: id,
            lang: lang,
            name: name,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String lang,
            required String name,
          }) =>
              SourcesCompanion.insert(
            id: id,
            lang: lang,
            name: name,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $SourcesProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    Sources,
    Source,
    $SourcesFilterComposer,
    $SourcesOrderingComposer,
    $SourcesAnnotationComposer,
    $SourcesCreateCompanionBuilder,
    $SourcesUpdateCompanionBuilder,
    (Source, BaseReferences<_$AppDatabase, Sources, Source>),
    Source,
    PrefetchHooks Function()>;
typedef $MangaSyncCreateCompanionBuilder = MangaSyncCompanion Function({
  Value<int> id,
  required int mangaId,
  required int syncId,
  required int remoteId,
  Value<int?> libraryId,
  required String title,
  required double lastChapterRead,
  required int totalChapters,
  required int status,
  required double score,
  required String remoteUrl,
  required int startDate,
  required int finishDate,
  Value<int> private,
});
typedef $MangaSyncUpdateCompanionBuilder = MangaSyncCompanion Function({
  Value<int> id,
  Value<int> mangaId,
  Value<int> syncId,
  Value<int> remoteId,
  Value<int?> libraryId,
  Value<String> title,
  Value<double> lastChapterRead,
  Value<int> totalChapters,
  Value<int> status,
  Value<double> score,
  Value<String> remoteUrl,
  Value<int> startDate,
  Value<int> finishDate,
  Value<int> private,
});

class $MangaSyncFilterComposer extends Composer<_$AppDatabase, MangaSync> {
  $MangaSyncFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get mangaId => $composableBuilder(
      column: $table.mangaId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get remoteId => $composableBuilder(
      column: $table.remoteId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get libraryId => $composableBuilder(
      column: $table.libraryId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get lastChapterRead => $composableBuilder(
      column: $table.lastChapterRead,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get totalChapters => $composableBuilder(
      column: $table.totalChapters, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get score => $composableBuilder(
      column: $table.score, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get remoteUrl => $composableBuilder(
      column: $table.remoteUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get startDate => $composableBuilder(
      column: $table.startDate, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get finishDate => $composableBuilder(
      column: $table.finishDate, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get private => $composableBuilder(
      column: $table.private, builder: (column) => ColumnFilters(column));
}

class $MangaSyncOrderingComposer extends Composer<_$AppDatabase, MangaSync> {
  $MangaSyncOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get mangaId => $composableBuilder(
      column: $table.mangaId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get remoteId => $composableBuilder(
      column: $table.remoteId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get libraryId => $composableBuilder(
      column: $table.libraryId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get lastChapterRead => $composableBuilder(
      column: $table.lastChapterRead,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get totalChapters => $composableBuilder(
      column: $table.totalChapters,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get score => $composableBuilder(
      column: $table.score, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get remoteUrl => $composableBuilder(
      column: $table.remoteUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get startDate => $composableBuilder(
      column: $table.startDate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get finishDate => $composableBuilder(
      column: $table.finishDate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get private => $composableBuilder(
      column: $table.private, builder: (column) => ColumnOrderings(column));
}

class $MangaSyncAnnotationComposer extends Composer<_$AppDatabase, MangaSync> {
  $MangaSyncAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get mangaId =>
      $composableBuilder(column: $table.mangaId, builder: (column) => column);

  GeneratedColumn<int> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<int> get remoteId =>
      $composableBuilder(column: $table.remoteId, builder: (column) => column);

  GeneratedColumn<int> get libraryId =>
      $composableBuilder(column: $table.libraryId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<double> get lastChapterRead => $composableBuilder(
      column: $table.lastChapterRead, builder: (column) => column);

  GeneratedColumn<int> get totalChapters => $composableBuilder(
      column: $table.totalChapters, builder: (column) => column);

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<double> get score =>
      $composableBuilder(column: $table.score, builder: (column) => column);

  GeneratedColumn<String> get remoteUrl =>
      $composableBuilder(column: $table.remoteUrl, builder: (column) => column);

  GeneratedColumn<int> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumn<int> get finishDate => $composableBuilder(
      column: $table.finishDate, builder: (column) => column);

  GeneratedColumn<int> get private =>
      $composableBuilder(column: $table.private, builder: (column) => column);
}

class $MangaSyncTableManager extends RootTableManager<
    _$AppDatabase,
    MangaSync,
    MangaSyncData,
    $MangaSyncFilterComposer,
    $MangaSyncOrderingComposer,
    $MangaSyncAnnotationComposer,
    $MangaSyncCreateCompanionBuilder,
    $MangaSyncUpdateCompanionBuilder,
    (MangaSyncData, BaseReferences<_$AppDatabase, MangaSync, MangaSyncData>),
    MangaSyncData,
    PrefetchHooks Function()> {
  $MangaSyncTableManager(_$AppDatabase db, MangaSync table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $MangaSyncFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $MangaSyncOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $MangaSyncAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> mangaId = const Value.absent(),
            Value<int> syncId = const Value.absent(),
            Value<int> remoteId = const Value.absent(),
            Value<int?> libraryId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<double> lastChapterRead = const Value.absent(),
            Value<int> totalChapters = const Value.absent(),
            Value<int> status = const Value.absent(),
            Value<double> score = const Value.absent(),
            Value<String> remoteUrl = const Value.absent(),
            Value<int> startDate = const Value.absent(),
            Value<int> finishDate = const Value.absent(),
            Value<int> private = const Value.absent(),
          }) =>
              MangaSyncCompanion(
            id: id,
            mangaId: mangaId,
            syncId: syncId,
            remoteId: remoteId,
            libraryId: libraryId,
            title: title,
            lastChapterRead: lastChapterRead,
            totalChapters: totalChapters,
            status: status,
            score: score,
            remoteUrl: remoteUrl,
            startDate: startDate,
            finishDate: finishDate,
            private: private,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int mangaId,
            required int syncId,
            required int remoteId,
            Value<int?> libraryId = const Value.absent(),
            required String title,
            required double lastChapterRead,
            required int totalChapters,
            required int status,
            required double score,
            required String remoteUrl,
            required int startDate,
            required int finishDate,
            Value<int> private = const Value.absent(),
          }) =>
              MangaSyncCompanion.insert(
            id: id,
            mangaId: mangaId,
            syncId: syncId,
            remoteId: remoteId,
            libraryId: libraryId,
            title: title,
            lastChapterRead: lastChapterRead,
            totalChapters: totalChapters,
            status: status,
            score: score,
            remoteUrl: remoteUrl,
            startDate: startDate,
            finishDate: finishDate,
            private: private,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $MangaSyncProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    MangaSync,
    MangaSyncData,
    $MangaSyncFilterComposer,
    $MangaSyncOrderingComposer,
    $MangaSyncAnnotationComposer,
    $MangaSyncCreateCompanionBuilder,
    $MangaSyncUpdateCompanionBuilder,
    (MangaSyncData, BaseReferences<_$AppDatabase, MangaSync, MangaSyncData>),
    MangaSyncData,
    PrefetchHooks Function()>;
typedef $ChaptersCreateCompanionBuilder = ChaptersCompanion Function({
  Value<int> id,
  required int mangaId,
  required String url,
  required String name,
  Value<String?> scanlator,
  required int read,
  required int bookmark,
  required int lastPageRead,
  required double chapterNumber,
  required int sourceOrder,
  required int dateFetch,
  required int dateUpload,
  Value<int> lastModifiedAt,
  Value<int> version,
  Value<int> isSyncing,
  Value<String?> bookmarkNote,
  Value<double?> volumeNumber,
});
typedef $ChaptersUpdateCompanionBuilder = ChaptersCompanion Function({
  Value<int> id,
  Value<int> mangaId,
  Value<String> url,
  Value<String> name,
  Value<String?> scanlator,
  Value<int> read,
  Value<int> bookmark,
  Value<int> lastPageRead,
  Value<double> chapterNumber,
  Value<int> sourceOrder,
  Value<int> dateFetch,
  Value<int> dateUpload,
  Value<int> lastModifiedAt,
  Value<int> version,
  Value<int> isSyncing,
  Value<String?> bookmarkNote,
  Value<double?> volumeNumber,
});

class $ChaptersFilterComposer extends Composer<_$AppDatabase, Chapters> {
  $ChaptersFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get mangaId => $composableBuilder(
      column: $table.mangaId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get url => $composableBuilder(
      column: $table.url, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get scanlator => $composableBuilder(
      column: $table.scanlator, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get read => $composableBuilder(
      column: $table.read, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get bookmark => $composableBuilder(
      column: $table.bookmark, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastPageRead => $composableBuilder(
      column: $table.lastPageRead, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get chapterNumber => $composableBuilder(
      column: $table.chapterNumber, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sourceOrder => $composableBuilder(
      column: $table.sourceOrder, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get dateFetch => $composableBuilder(
      column: $table.dateFetch, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get dateUpload => $composableBuilder(
      column: $table.dateUpload, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastModifiedAt => $composableBuilder(
      column: $table.lastModifiedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get isSyncing => $composableBuilder(
      column: $table.isSyncing, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get bookmarkNote => $composableBuilder(
      column: $table.bookmarkNote, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get volumeNumber => $composableBuilder(
      column: $table.volumeNumber, builder: (column) => ColumnFilters(column));
}

class $ChaptersOrderingComposer extends Composer<_$AppDatabase, Chapters> {
  $ChaptersOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get mangaId => $composableBuilder(
      column: $table.mangaId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get url => $composableBuilder(
      column: $table.url, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get scanlator => $composableBuilder(
      column: $table.scanlator, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get read => $composableBuilder(
      column: $table.read, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get bookmark => $composableBuilder(
      column: $table.bookmark, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastPageRead => $composableBuilder(
      column: $table.lastPageRead,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get chapterNumber => $composableBuilder(
      column: $table.chapterNumber,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sourceOrder => $composableBuilder(
      column: $table.sourceOrder, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get dateFetch => $composableBuilder(
      column: $table.dateFetch, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get dateUpload => $composableBuilder(
      column: $table.dateUpload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastModifiedAt => $composableBuilder(
      column: $table.lastModifiedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get isSyncing => $composableBuilder(
      column: $table.isSyncing, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get bookmarkNote => $composableBuilder(
      column: $table.bookmarkNote,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get volumeNumber => $composableBuilder(
      column: $table.volumeNumber,
      builder: (column) => ColumnOrderings(column));
}

class $ChaptersAnnotationComposer extends Composer<_$AppDatabase, Chapters> {
  $ChaptersAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get mangaId =>
      $composableBuilder(column: $table.mangaId, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get scanlator =>
      $composableBuilder(column: $table.scanlator, builder: (column) => column);

  GeneratedColumn<int> get read =>
      $composableBuilder(column: $table.read, builder: (column) => column);

  GeneratedColumn<int> get bookmark =>
      $composableBuilder(column: $table.bookmark, builder: (column) => column);

  GeneratedColumn<int> get lastPageRead => $composableBuilder(
      column: $table.lastPageRead, builder: (column) => column);

  GeneratedColumn<double> get chapterNumber => $composableBuilder(
      column: $table.chapterNumber, builder: (column) => column);

  GeneratedColumn<int> get sourceOrder => $composableBuilder(
      column: $table.sourceOrder, builder: (column) => column);

  GeneratedColumn<int> get dateFetch =>
      $composableBuilder(column: $table.dateFetch, builder: (column) => column);

  GeneratedColumn<int> get dateUpload => $composableBuilder(
      column: $table.dateUpload, builder: (column) => column);

  GeneratedColumn<int> get lastModifiedAt => $composableBuilder(
      column: $table.lastModifiedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<int> get isSyncing =>
      $composableBuilder(column: $table.isSyncing, builder: (column) => column);

  GeneratedColumn<String> get bookmarkNote => $composableBuilder(
      column: $table.bookmarkNote, builder: (column) => column);

  GeneratedColumn<double> get volumeNumber => $composableBuilder(
      column: $table.volumeNumber, builder: (column) => column);
}

class $ChaptersTableManager extends RootTableManager<
    _$AppDatabase,
    Chapters,
    Chapter,
    $ChaptersFilterComposer,
    $ChaptersOrderingComposer,
    $ChaptersAnnotationComposer,
    $ChaptersCreateCompanionBuilder,
    $ChaptersUpdateCompanionBuilder,
    (Chapter, BaseReferences<_$AppDatabase, Chapters, Chapter>),
    Chapter,
    PrefetchHooks Function()> {
  $ChaptersTableManager(_$AppDatabase db, Chapters table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ChaptersFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ChaptersOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ChaptersAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> mangaId = const Value.absent(),
            Value<String> url = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> scanlator = const Value.absent(),
            Value<int> read = const Value.absent(),
            Value<int> bookmark = const Value.absent(),
            Value<int> lastPageRead = const Value.absent(),
            Value<double> chapterNumber = const Value.absent(),
            Value<int> sourceOrder = const Value.absent(),
            Value<int> dateFetch = const Value.absent(),
            Value<int> dateUpload = const Value.absent(),
            Value<int> lastModifiedAt = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<int> isSyncing = const Value.absent(),
            Value<String?> bookmarkNote = const Value.absent(),
            Value<double?> volumeNumber = const Value.absent(),
          }) =>
              ChaptersCompanion(
            id: id,
            mangaId: mangaId,
            url: url,
            name: name,
            scanlator: scanlator,
            read: read,
            bookmark: bookmark,
            lastPageRead: lastPageRead,
            chapterNumber: chapterNumber,
            sourceOrder: sourceOrder,
            dateFetch: dateFetch,
            dateUpload: dateUpload,
            lastModifiedAt: lastModifiedAt,
            version: version,
            isSyncing: isSyncing,
            bookmarkNote: bookmarkNote,
            volumeNumber: volumeNumber,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int mangaId,
            required String url,
            required String name,
            Value<String?> scanlator = const Value.absent(),
            required int read,
            required int bookmark,
            required int lastPageRead,
            required double chapterNumber,
            required int sourceOrder,
            required int dateFetch,
            required int dateUpload,
            Value<int> lastModifiedAt = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<int> isSyncing = const Value.absent(),
            Value<String?> bookmarkNote = const Value.absent(),
            Value<double?> volumeNumber = const Value.absent(),
          }) =>
              ChaptersCompanion.insert(
            id: id,
            mangaId: mangaId,
            url: url,
            name: name,
            scanlator: scanlator,
            read: read,
            bookmark: bookmark,
            lastPageRead: lastPageRead,
            chapterNumber: chapterNumber,
            sourceOrder: sourceOrder,
            dateFetch: dateFetch,
            dateUpload: dateUpload,
            lastModifiedAt: lastModifiedAt,
            version: version,
            isSyncing: isSyncing,
            bookmarkNote: bookmarkNote,
            volumeNumber: volumeNumber,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $ChaptersProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    Chapters,
    Chapter,
    $ChaptersFilterComposer,
    $ChaptersOrderingComposer,
    $ChaptersAnnotationComposer,
    $ChaptersCreateCompanionBuilder,
    $ChaptersUpdateCompanionBuilder,
    (Chapter, BaseReferences<_$AppDatabase, Chapters, Chapter>),
    Chapter,
    PrefetchHooks Function()>;
typedef $HistoryCreateCompanionBuilder = HistoryCompanion Function({
  Value<int> id,
  required int chapterId,
  Value<int?> lastRead,
  required int timeRead,
});
typedef $HistoryUpdateCompanionBuilder = HistoryCompanion Function({
  Value<int> id,
  Value<int> chapterId,
  Value<int?> lastRead,
  Value<int> timeRead,
});

class $HistoryFilterComposer extends Composer<_$AppDatabase, History> {
  $HistoryFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get chapterId => $composableBuilder(
      column: $table.chapterId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastRead => $composableBuilder(
      column: $table.lastRead, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get timeRead => $composableBuilder(
      column: $table.timeRead, builder: (column) => ColumnFilters(column));
}

class $HistoryOrderingComposer extends Composer<_$AppDatabase, History> {
  $HistoryOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get chapterId => $composableBuilder(
      column: $table.chapterId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastRead => $composableBuilder(
      column: $table.lastRead, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get timeRead => $composableBuilder(
      column: $table.timeRead, builder: (column) => ColumnOrderings(column));
}

class $HistoryAnnotationComposer extends Composer<_$AppDatabase, History> {
  $HistoryAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get chapterId =>
      $composableBuilder(column: $table.chapterId, builder: (column) => column);

  GeneratedColumn<int> get lastRead =>
      $composableBuilder(column: $table.lastRead, builder: (column) => column);

  GeneratedColumn<int> get timeRead =>
      $composableBuilder(column: $table.timeRead, builder: (column) => column);
}

class $HistoryTableManager extends RootTableManager<
    _$AppDatabase,
    History,
    HistoryData,
    $HistoryFilterComposer,
    $HistoryOrderingComposer,
    $HistoryAnnotationComposer,
    $HistoryCreateCompanionBuilder,
    $HistoryUpdateCompanionBuilder,
    (HistoryData, BaseReferences<_$AppDatabase, History, HistoryData>),
    HistoryData,
    PrefetchHooks Function()> {
  $HistoryTableManager(_$AppDatabase db, History table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $HistoryFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $HistoryOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $HistoryAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> chapterId = const Value.absent(),
            Value<int?> lastRead = const Value.absent(),
            Value<int> timeRead = const Value.absent(),
          }) =>
              HistoryCompanion(
            id: id,
            chapterId: chapterId,
            lastRead: lastRead,
            timeRead: timeRead,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int chapterId,
            Value<int?> lastRead = const Value.absent(),
            required int timeRead,
          }) =>
              HistoryCompanion.insert(
            id: id,
            chapterId: chapterId,
            lastRead: lastRead,
            timeRead: timeRead,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $HistoryProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    History,
    HistoryData,
    $HistoryFilterComposer,
    $HistoryOrderingComposer,
    $HistoryAnnotationComposer,
    $HistoryCreateCompanionBuilder,
    $HistoryUpdateCompanionBuilder,
    (HistoryData, BaseReferences<_$AppDatabase, History, HistoryData>),
    HistoryData,
    PrefetchHooks Function()>;
typedef $CategoriesCreateCompanionBuilder = CategoriesCompanion Function({
  Value<int> id,
  required String name,
  required int sort,
  required int flags,
  Value<int?> parentId,
});
typedef $CategoriesUpdateCompanionBuilder = CategoriesCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<int> sort,
  Value<int> flags,
  Value<int?> parentId,
});

class $CategoriesFilterComposer extends Composer<_$AppDatabase, Categories> {
  $CategoriesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sort => $composableBuilder(
      column: $table.sort, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get flags => $composableBuilder(
      column: $table.flags, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get parentId => $composableBuilder(
      column: $table.parentId, builder: (column) => ColumnFilters(column));
}

class $CategoriesOrderingComposer extends Composer<_$AppDatabase, Categories> {
  $CategoriesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sort => $composableBuilder(
      column: $table.sort, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get flags => $composableBuilder(
      column: $table.flags, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get parentId => $composableBuilder(
      column: $table.parentId, builder: (column) => ColumnOrderings(column));
}

class $CategoriesAnnotationComposer
    extends Composer<_$AppDatabase, Categories> {
  $CategoriesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sort =>
      $composableBuilder(column: $table.sort, builder: (column) => column);

  GeneratedColumn<int> get flags =>
      $composableBuilder(column: $table.flags, builder: (column) => column);

  GeneratedColumn<int> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);
}

class $CategoriesTableManager extends RootTableManager<
    _$AppDatabase,
    Categories,
    Category,
    $CategoriesFilterComposer,
    $CategoriesOrderingComposer,
    $CategoriesAnnotationComposer,
    $CategoriesCreateCompanionBuilder,
    $CategoriesUpdateCompanionBuilder,
    (Category, BaseReferences<_$AppDatabase, Categories, Category>),
    Category,
    PrefetchHooks Function()> {
  $CategoriesTableManager(_$AppDatabase db, Categories table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $CategoriesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $CategoriesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $CategoriesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> sort = const Value.absent(),
            Value<int> flags = const Value.absent(),
            Value<int?> parentId = const Value.absent(),
          }) =>
              CategoriesCompanion(
            id: id,
            name: name,
            sort: sort,
            flags: flags,
            parentId: parentId,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            required int sort,
            required int flags,
            Value<int?> parentId = const Value.absent(),
          }) =>
              CategoriesCompanion.insert(
            id: id,
            name: name,
            sort: sort,
            flags: flags,
            parentId: parentId,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $CategoriesProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    Categories,
    Category,
    $CategoriesFilterComposer,
    $CategoriesOrderingComposer,
    $CategoriesAnnotationComposer,
    $CategoriesCreateCompanionBuilder,
    $CategoriesUpdateCompanionBuilder,
    (Category, BaseReferences<_$AppDatabase, Categories, Category>),
    Category,
    PrefetchHooks Function()>;
typedef $MangasCategoriesCreateCompanionBuilder = MangasCategoriesCompanion
    Function({
  Value<int> id,
  required int mangaId,
  required int categoryId,
});
typedef $MangasCategoriesUpdateCompanionBuilder = MangasCategoriesCompanion
    Function({
  Value<int> id,
  Value<int> mangaId,
  Value<int> categoryId,
});

class $MangasCategoriesFilterComposer
    extends Composer<_$AppDatabase, MangasCategories> {
  $MangasCategoriesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get mangaId => $composableBuilder(
      column: $table.mangaId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnFilters(column));
}

class $MangasCategoriesOrderingComposer
    extends Composer<_$AppDatabase, MangasCategories> {
  $MangasCategoriesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get mangaId => $composableBuilder(
      column: $table.mangaId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnOrderings(column));
}

class $MangasCategoriesAnnotationComposer
    extends Composer<_$AppDatabase, MangasCategories> {
  $MangasCategoriesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get mangaId =>
      $composableBuilder(column: $table.mangaId, builder: (column) => column);

  GeneratedColumn<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => column);
}

class $MangasCategoriesTableManager extends RootTableManager<
    _$AppDatabase,
    MangasCategories,
    MangasCategory,
    $MangasCategoriesFilterComposer,
    $MangasCategoriesOrderingComposer,
    $MangasCategoriesAnnotationComposer,
    $MangasCategoriesCreateCompanionBuilder,
    $MangasCategoriesUpdateCompanionBuilder,
    (
      MangasCategory,
      BaseReferences<_$AppDatabase, MangasCategories, MangasCategory>
    ),
    MangasCategory,
    PrefetchHooks Function()> {
  $MangasCategoriesTableManager(_$AppDatabase db, MangasCategories table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $MangasCategoriesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $MangasCategoriesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $MangasCategoriesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> mangaId = const Value.absent(),
            Value<int> categoryId = const Value.absent(),
          }) =>
              MangasCategoriesCompanion(
            id: id,
            mangaId: mangaId,
            categoryId: categoryId,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int mangaId,
            required int categoryId,
          }) =>
              MangasCategoriesCompanion.insert(
            id: id,
            mangaId: mangaId,
            categoryId: categoryId,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $MangasCategoriesProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    MangasCategories,
    MangasCategory,
    $MangasCategoriesFilterComposer,
    $MangasCategoriesOrderingComposer,
    $MangasCategoriesAnnotationComposer,
    $MangasCategoriesCreateCompanionBuilder,
    $MangasCategoriesUpdateCompanionBuilder,
    (
      MangasCategory,
      BaseReferences<_$AppDatabase, MangasCategories, MangasCategory>
    ),
    MangasCategory,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $MangasTableManager get mangas => $MangasTableManager(_db, _db.mangas);
  $MangaLinksTableManager get mangaLinks =>
      $MangaLinksTableManager(_db, _db.mangaLinks);
  $ExtensionReposTableManager get extensionRepos =>
      $ExtensionReposTableManager(_db, _db.extensionRepos);
  $ScanlatorPriorityTableManager get scanlatorPriority =>
      $ScanlatorPriorityTableManager(_db, _db.scanlatorPriority);
  $ExcludedScanlatorsTableManager get excludedScanlators =>
      $ExcludedScanlatorsTableManager(_db, _db.excludedScanlators);
  $SourcesTableManager get sources => $SourcesTableManager(_db, _db.sources);
  $MangaSyncTableManager get mangaSync =>
      $MangaSyncTableManager(_db, _db.mangaSync);
  $ChaptersTableManager get chapters =>
      $ChaptersTableManager(_db, _db.chapters);
  $HistoryTableManager get history => $HistoryTableManager(_db, _db.history);
  $CategoriesTableManager get categories =>
      $CategoriesTableManager(_db, _db.categories);
  $MangasCategoriesTableManager get mangasCategories =>
      $MangasCategoriesTableManager(_db, _db.mangasCategories);
}

class GetLinksForPrimaryResult {
  final int linkedMangaId;
  final int priority;
  GetLinksForPrimaryResult({
    required this.linkedMangaId,
    required this.priority,
  });
}

class GetAllLinksForBackupResult {
  final int primarySource;
  final String primaryUrl;
  final int linkedSource;
  final String linkedUrl;
  final int priority;
  GetAllLinksForBackupResult({
    required this.primarySource,
    required this.primaryUrl,
    required this.linkedSource,
    required this.linkedUrl,
    required this.priority,
  });
}

class GetAllLinkedWithPrimaryResult {
  final int linkedMangaId;
  final int id;
  final int source;
  final String url;
  final String? artist;
  final String? author;
  final String? description;
  final String? genre;
  final String title;
  final int status;
  final String? thumbnailUrl;
  final int favorite;
  final int? lastUpdate;
  final int? nextUpdate;
  final int initialized;
  final int viewer;
  final int chapterFlags;
  final int coverLastModified;
  final int dateAdded;
  final int updateStrategy;
  final int calculateInterval;
  final int lastModifiedAt;
  final int? favoriteModifiedAt;
  final int version;
  final int isSyncing;
  final String notes;
  GetAllLinkedWithPrimaryResult({
    required this.linkedMangaId,
    required this.id,
    required this.source,
    required this.url,
    this.artist,
    this.author,
    this.description,
    this.genre,
    required this.title,
    required this.status,
    this.thumbnailUrl,
    required this.favorite,
    this.lastUpdate,
    this.nextUpdate,
    required this.initialized,
    required this.viewer,
    required this.chapterFlags,
    required this.coverLastModified,
    required this.dateAdded,
    required this.updateStrategy,
    required this.calculateInterval,
    required this.lastModifiedAt,
    this.favoriteModifiedAt,
    required this.version,
    required this.isSyncing,
    required this.notes,
  });
}

class GetPrioritiesByMangaIdResult {
  final String scanlator;
  final int priority;
  GetPrioritiesByMangaIdResult({
    required this.scanlator,
    required this.priority,
  });
}
