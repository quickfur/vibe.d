/**
	MongoDatabase class representing common database for group of collections.

	Technically it is very special collection with common query functions
	disabled and some service commands provided.

	Copyright: © 2012-2014 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.database;

import vibe.db.mongo.client;
import vibe.db.mongo.collection;
import vibe.data.bson;


/** Represents a single database accessible through a given MongoClient.
*/
struct MongoDatabase
{
@safe:

	private {
		string m_name;
		MongoClient m_client;
	}

	//@disable this();

	this(MongoClient client, string name)
	{
		import std.algorithm;

		assert(client !is null);
		m_client = client;

		assert(
				!canFind(name, '.'),
				"Compound collection path provided to MongoDatabase constructor instead of single database name"
		  );
		m_name = name;
	}

	/// The name of this database
	@property string name()
	{
		return m_name;
	}

	/// The client which represents the connection to the database server
	@property MongoClient client()
	{
		return m_client;
	}

	/** Accesses the collections of this database.

		Returns: The collection with the given name
	*/
	MongoCollection opIndex(string name)
	{
		return MongoCollection(this, name);
	}

	/** Retrieves the last error code (if any) from the database server.

		Exact object format is not documented. MongoErrorDescription signature will be
		updated upon any issues. Note that this method will execute a query to service
		collection and thus is far from being "free".

		Returns: struct storing data from MongoDB db.getLastErrorObj() object
 	*/
	MongoErrorDescription getLastError()
	{
		return m_client.lockConnection().getLastError(m_name);
	}

	/** Returns recent log messages for this database from the database server.

		See $(LINK http://www.mongodb.org/display/DOCS/getLog+Command).

	 	Params:
	 		mask = "global" or "rs" or "startupWarnings". Refer to official MongoDB docs.

	 	Returns: Bson document with recent log messages from MongoDB service.
 	 */
	Bson getLog(string mask)
	{
		static struct CMD {
			string getLog;
		}
		CMD cmd;
		cmd.getLog = mask;
		return runCommand(cmd, true);
	}

	/** Performs a filesystem/disk sync of the database on the server.

		See $(LINK http://www.mongodb.org/display/DOCS/fsync+Command)

		Returns: check documentation
 	 */
	Bson fsync(bool async = false)
	{
		static struct CMD {
			int fsync = 1;
			bool async;
		}
		CMD cmd;
		cmd.async = async;
		return runCommand(cmd, true);
	}


	/** Generic means to run commands on the database.

		See $(LINK http://www.mongodb.org/display/DOCS/Commands) for a list
		of possible values for command_and_options.

		Note that some commands return a cursor instead of a single document.
		In this case, use `runListCommand` instead of `runCommand` to be able
		to properly iterate over the results.

		Params:
			command_and_options = Bson object containing the command to be executed
				as well as the command parameters as fields
			checkOk = usually commands respond with a `double ok` field in them,
				which is not checked if this parameter is false. Explicitly
				specify this parameter to avoid issues with error checking.
				Currently defaults to `false` (meaning don't check "ok" field),
				omitting the argument may change to `true` in the future.

		Returns: The raw response of the MongoDB server
	*/
	deprecated("use runCommand with explicit checkOk overload")
	Bson runCommand(T)(T command_and_options,
		string errorInfo = __FUNCTION__, string errorFile = __FILE__, size_t errorLine = __LINE__)
	{
		return runCommand(command_and_options, false, errorInfo, errorFile, errorLine);
	}
	/// ditto
	Bson runCommand(T)(T command_and_options, bool checkOk,
		string errorInfo = __FUNCTION__, string errorFile = __FILE__, size_t errorLine = __LINE__)
	{
		Bson cmd;
		static if (is(T : Bson))
			cmd = command_and_options;
		else
			cmd = command_and_options.serializeToBson;
		return m_client.lockConnection().runCommand!(Bson, MongoException)(m_name, cmd, checkOk, errorInfo, errorFile, errorLine);
	}
	/// ditto
	MongoCursor!R runListCommand(R = Bson, T)(T command_and_options)
	{
		auto cur = runCommand(command_and_options, true);

		// TODO: use cursor API
		auto cursorid = cur["cursor"]["id"].get!long;
		static if (is(R == Bson))
			auto existing = cur["cursor"]["firstBatch"].get!(Bson[]);
		else auto existing = cur["cursor"]["firstBatch"].deserializeBson!(R[]);
		return MongoCursor!R(m_client, m_commandCollection, cursorid, existing);
	}
}
