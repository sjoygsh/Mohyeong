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

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final Mangas mangas = Mangas(this);
  late final Chapters chapters = Chapters(this);
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
        chapters,
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
              TableUpdate('chapters', kind: UpdateKind.delete),
            ],
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

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $MangasTableManager get mangas => $MangasTableManager(_db, _db.mangas);
  $ChaptersTableManager get chapters =>
      $ChaptersTableManager(_db, _db.chapters);
}
