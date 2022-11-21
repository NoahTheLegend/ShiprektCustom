#include "MakeBlock.as";

void onInit(CRules@ this)
{
	u16[] motherships(8); // length is the amount of teams on the gamemode (8)
	this.set("motherships", motherships);
	
	onRestart(this);
}

void onRestart(CRules@ this)
{
	if (!isServer()) return;
	this.set_u8("rand", XORRandom(4));
	Vec2f[] spawns;
	const Vec2f spawnOffset(4.0f, 4.0f); //align to tilegrid
	if (getMap().getMarkers("spawn", spawns))
	{
		const u8 specTeam = this.getSpectatorTeamNum();
		u8 pCount = getPlayerCount();
		for (u8 p = 0; p < pCount; p++)//discard spectators
		{
			CPlayer@ player = getPlayer(p);
			if (player.getTeamNum() == specTeam)
				pCount--;
		}
		
		const u8 availableCores = Maths::Min(spawns.length, this.getTeamsNum());
		const u8 playingCores = pCount == 3 ? 3 : Maths::Max(2, int(Maths::Floor(pCount/2)));//special case for 3 players
		const u8 mShipsToSpawn = Maths::Min(playingCores, availableCores);
		print("** Spawning " + mShipsToSpawn + " motherships of " + availableCores + " for " + pCount + " players");
		
		for (u8 s = 0; s < mShipsToSpawn; s++)
		{
			const u8 randomSpawn = XORRandom(spawns.length);
			SpawnMothership(spawns[randomSpawn] + spawnOffset, s);
			
			spawns.erase(randomSpawn);
		}
	}
}

void SpawnMothership(Vec2f pos, const u8&in team)
{
	u8 rand = getRules().get_u8("rand"); // make a random ship so auuuuuuuugh

	switch (rand)
	{
		case 0: // default ship
		{
			// platforms

			makeBlock(pos + Vec2f(-8, -8), 0.0f, "platform", team);
			makeBlock(pos + Vec2f(0, -8), 0.0f, "platform", team);
			makeBlock(pos + Vec2f(8, -8), 0.0f, "platform", team);

			makeBlock(pos + Vec2f(-8, 0), 0.0f, "platform", team);	
			makeBlock(pos, 0.0f, "mothership", team);
			makeBlock(pos + Vec2f(8, 0), 0.0f, "platform", team);

			makeBlock(pos + Vec2f(-8, 8), 0.0f, "platform", team);
			makeBlock(pos + Vec2f(0, 8), 0.0f, "platform", team);
			makeBlock(pos + Vec2f(8, 8), 0.0f, "platform", team);

			// surrounding

			makeBlock(pos + Vec2f(-8*2, -8*1), 0.0f, "solid", team);
			makeBlock(pos + Vec2f(-8*2, -8*2), 0.0f, "solid", team);
			makeBlock(pos + Vec2f(-8*1, -8*2), 0.0f, "solid", team);

			makeOuterPlatform(pos + Vec2f(0, -8*2), team);

			makeBlock(pos + Vec2f(8*1, -8*2), 0.0f, "solid", team);
			makeBlock(pos + Vec2f(8*2, -8*2), 0.0f, "solid", team);
			makeBlock(pos + Vec2f(8*2, -8*1), 0.0f, "solid", team);

			makeOuterPlatform(pos + Vec2f(8*2, 0), team);

			makeBlock(pos + Vec2f(8*2, 8*1), 0.0f, "solid", team);
			makeBlock(pos + Vec2f(8*2, 8*2), 0.0f, "solid", team);
			makeBlock(pos + Vec2f(8*1, 8*2), 0.0f, "solid", team);

			makeOuterPlatform(pos + Vec2f(0, 8*2), team);

			makeBlock(pos + Vec2f(-8*1, 8*2), 0.0f, "solid", team);
			makeBlock(pos + Vec2f(-8*2, 8*2), 0.0f, "solid", team);
			makeBlock(pos + Vec2f(-8*2, 8*1), 0.0f, "solid", team);

			makeOuterPlatform(pos + Vec2f(-8*2, 0), team);

			break;
		}
		case 1: // long ship
		{
			makeBlock(pos + Vec2f(0, -8), 0.0f, "platform", team);
			makeBlock(pos + Vec2f(0, -8*2), 0.0f, "platform", team);	
			makeBlock(pos + Vec2f(0, -8*3), 0.0f, "platform", team);	
			makeBlock(pos + Vec2f(0, -8*4), 0.0f, "platform", team);	
			makeBlock(pos + Vec2f(-8, 0), 0.0f, "platform", team);	
			makeBlock(pos, 0.0f, "mothership", team);
			makeBlock(pos + Vec2f(8, 0), 0.0f, "platform", team);

			makeBlock(pos + Vec2f(0, 8), 0.0f, "platform", team);
			makeBlock(pos + Vec2f(0, 8*2), 0.0f, "platform", team);	
			makeBlock(pos + Vec2f(0, -8*5), 0.0f, "platform", team);	

			makeEngine(pos + Vec2f(-8, -8*2), team, 0, "propeller");
			makeEngine(pos + Vec2f(8, -8*2), team, 0, "propeller");
			makeEngine(pos + Vec2f(-8, 8), team, 0, "propeller");
			makeEngine(pos + Vec2f(8, 8), team, 0, "propeller");

			makeEngine(pos + Vec2f(-8, 8*3), team, 1, "propeller");
			makeEngine(pos + Vec2f(8, 8*3), team, 3, "propeller");

			// surrounding

			makeBlock(pos + Vec2f(-8*2, -8*1), 0.0f, "solid", team);
			makeBlock(pos + Vec2f(-8*2, -8*2), 0.0f, "solid", team);

			makeBlock(pos + Vec2f(8*2, -8*2), 0.0f, "solid", team);
			makeBlock(pos + Vec2f(8*2, -8*1), 0.0f, "solid", team);

			makeBlock(pos + Vec2f(-8*1, -8*5), 0.0f, "solid", team);
			makeBlock(pos + Vec2f(-8*1, -8*4), 0.0f, "solid", team);
			makeBlock(pos + Vec2f(-8*1, -8*3), 0.0f, "solid", team);

			makeOuterPlatform(pos + Vec2f(0, -8*6), team);

			makeBlock(pos + Vec2f(8*1, -8*5), 0.0f, "solid", team);
			makeBlock(pos + Vec2f(8*1, -8*4), 0.0f, "solid", team);
			makeBlock(pos + Vec2f(8*1, -8*3), 0.0f, "solid", team);

			makeOuterPlatform(pos + Vec2f(8*2, 0), team);

			makeBlock(pos + Vec2f(8*2, 8*1), 0.0f, "solid", team);
			makeBlock(pos + Vec2f(8*2, 8*2), 0.0f, "solid", team);

			makeOuterPlatform(pos + Vec2f(0, 8*3), team);

			makeBlock(pos + Vec2f(-8*2, 8*2), 0.0f, "solid", team);
			makeBlock(pos + Vec2f(-8*2, 8*1), 0.0f, "solid", team);

			makeOuterPlatform(pos + Vec2f(-8*2, 0), team);

			break;
			break;
		}
		case 2: // raft
		{
			makeBlock(pos, 0.0f, "mothership", team);
			makeOuterPlatform(pos + Vec2f(-8, 0), team);
			makeOuterPlatform(pos + Vec2f(8, 0), team);
			makeOuterPlatform(pos + Vec2f(-8, -8), team);
			makeOuterPlatform(pos + Vec2f(8, -8), team);
			makeOuterPlatform(pos + Vec2f(0, -8), team);
			makeOuterPlatform(pos + Vec2f(-8, 8), team);
			makeOuterPlatform(pos + Vec2f(8, 8), team);
			makeOuterPlatform(pos + Vec2f(0, 8), team);

			break;
		}
		case 3: // big ship
		{
			makeBlock(pos, 0.0f, "mothership", team);
			makeOuterPlatform(pos + Vec2f(-8*3, 0), team);
			makeOuterPlatform(pos + Vec2f(8*3, 0), team);
			makeBlock(pos + Vec2f(0, -8), 0.0f, "door", team);
			makeBlock(pos + Vec2f(0, 8), 0.0f, "door", team);

			makeBlock(pos + Vec2f(0, 8*2), 0.0f, "platform", team);
			makeBlock(pos + Vec2f(0, 8*3), 0.0f, "platform", team);
			makeBlock(pos + Vec2f(0, 8*4), 0.0f, "platform", team);
			makeBlock(pos + Vec2f(0, -8*2), 0.0f, "platform", team);
			makeBlock(pos + Vec2f(0, -8*3), 0.0f, "platform", team);
			makeBlock(pos + Vec2f(0, -8*4), 0.0f, "platform", team);

			makeBlock(pos + Vec2f(0, 8*5), 0.0f, "door", team);
			makeBlock(pos + Vec2f(0, -8*5), 0.0f, "door", team);
			makeHarpoon(pos + Vec2f(0, 8*6), team, 1);
			makeHarpoon(pos + Vec2f(0, -8*6), team, 3);
			makeBlock(pos + Vec2f(8, 8*6), 0.0f, "platform", team);
			makeBlock(pos + Vec2f(-8, 8*6), 0.0f, "platform", team);
			makeBlock(pos + Vec2f(8, -8*6), 0.0f, "platform", team);
			makeBlock(pos + Vec2f(-8, -8*6), 0.0f, "platform", team);

			makeEngine(pos + Vec2f(-8, 8*2), team, 0, "ramengine");
			makeEngine(pos + Vec2f(8, 8*2), team, 0, "ramengine");
			makeEngine(pos + Vec2f(-8, 8*4), team, 2, "ramengine");
			makeEngine(pos + Vec2f(8, 8*4), team, 2, "ramengine");
			makeEngine(pos + Vec2f(-8, -8*2), team, 2, "ramengine");
			makeEngine(pos + Vec2f(8, -8*2), team, 2, "ramengine");
			makeEngine(pos + Vec2f(-8, -8*4), team, 0, "ramengine");
			makeEngine(pos + Vec2f(8, -8*4), team, 0, "ramengine");

			makeBlock(pos + Vec2f(-8*3, 8), 0.0f, "solid", team);
			makeBlock(pos + Vec2f(-8*3, -8), 0.0f, "solid", team);
			makeBlock(pos + Vec2f(8*3, 8), 0.0f, "solid", team);
			makeBlock(pos + Vec2f(8*3, -8), 0.0f, "solid", team);

			makeBlock(pos + Vec2f(-8, 8*5), 0.0f, "solid", team);
			makeBlock(pos + Vec2f(-8, -8*5), 0.0f, "solid", team);
			makeBlock(pos + Vec2f(8, 8*5), 0.0f, "solid", team);
			makeBlock(pos + Vec2f(8, -8*5), 0.0f, "solid", team);

			makeEngine(pos + Vec2f(-8*2, 8), team, 2, "propeller");
			makeEngine(pos + Vec2f(-8*2, -8), team, 0, "propeller");
			makeEngine(pos + Vec2f(-8*1, 8), team, 2, "propeller");
			makeEngine(pos + Vec2f(-8*1, -8), team, 0, "propeller");

			makeEngine(pos + Vec2f(8*2, 8), team, 2, "propeller");
			makeEngine(pos + Vec2f(8*2, -8), team, 0, "propeller");
			makeEngine(pos + Vec2f(8*1, 8), team, 2, "propeller");
			makeEngine(pos + Vec2f(8*1, -8), team, 0, "propeller");
		}
	}
}

void makeHarpoon(Vec2f pos, const u8&in team, u8 rotation)
{
	CBlob@ block = server_CreateBlob("harpoon", team, pos);
	if (block !is null) 
	{
		block.setAngleDegrees(90 * rotation);
		block.getShape().getVars().customData = 0;
		block.set_u32("placedTime", getGameTime());
	}
}

void makeEngine(Vec2f pos, const u8&in team, u8 rotation, string name)
{
	CBlob@ block = server_CreateBlob(name, team, pos);
	if (block !is null) 
	{
		block.setAngleDegrees(90 * rotation);
		block.getShape().getVars().customData = 0;
		block.set_u32("placedTime", getGameTime());
	}
}

void makeOuterPlatform(Vec2f pos, const u8&in team)
{
	CBlob@ platform = makeBlock(pos, 0.0f, "platform", team);
	CSprite@ sprite = platform.getSprite();
	sprite.SetFrame(3);
	platform.Tag("noDamageAnim");
	if (isClient())
	{
		Animation@ anim = sprite.getAnimation("default");
		anim.AddFrame(3);
		anim.SetFrameIndex(3);
	}
}

bool onServerProcessChat(CRules@ this, const string& in text_in, string& out text_out, CPlayer@ player)
{
	if (player is null) return true;

	if (sv_test || player.isMod())
	{
		if (text_in.substr(0,1) == "!")
		{
			string[]@ tokens = text_in.split(" ");

			if (tokens.length > 1)
			{
				CBlob@ pBlob = player.getBlob();
				if (pBlob is null) return false;
				
				if (tokens[0] == "!spawnmothership") //spawn a mothership
				{
					SpawnMothership(pBlob.getPosition(), parseInt(tokens[1]));
				}
			}
		}
	}
	return true;
}
