#include "ExplosionEffects.as";;
#include "AccurateSoundPlay.as";
#include "ParticleSpark.as";
#include "Hitters.as";
#include "PlankCommon.as";
#include "WaterEffects.as";
#include "DamageBooty.as";

const f32 SPLASH_RADIUS = 12.0f;
const f32 SPLASH_DAMAGE = 2.25f;
const f32 MORTAR_REACH = 4.0f;

BootyRewards@ booty_reward;

void onInit(CBlob@ this)
{
	this.Tag("mortar shell");
	this.Tag("projectile");

	if (booty_reward is null)
	{
		BootyRewards _booty_reward;
		_booty_reward.addTagReward("bomb", 2);
		_booty_reward.addTagReward("engine", 1);
		_booty_reward.addTagReward("weapon", 2);
		_booty_reward.addTagReward("core", 4);
		@booty_reward = _booty_reward;
	}

	this.set_f32("scale", 1.0);

	ShapeConsts@ consts = this.getShape().getConsts();
    consts.mapCollisions = false;
	consts.bullet = true;	

	this.getSprite().SetZ(550.0f);
	
	//shake screen (onInit accounts for firing latency)
	CPlayer@ localPlayer = getLocalPlayer();
	if (localPlayer !is null && localPlayer is this.getDamageOwnerPlayer())
		ShakeScreen(4, 4, this.getPosition());

	CSprite@ sprite = this.getSprite();
	if (sprite !is null)
	{
		sprite.ScaleBy(Vec2f(0.4, 0.4));
	}

	this.set_bool("left", false);
	if (XORRandom(2) == 0)
	{
		this.set_bool("left", true);
	}
}

void onTick(CBlob@ this)
{
	f32 time = this.get_f32("timeScaling");
	f32 timesince = this.getTickSinceCreated();
    f32 res;
    if (time > 0) res = (100*timesince/time) / 45; // scaling from 0 to 75
	//printf(""+res);
	f32 scale = (100.0 - res*1.0)*0.0004;
	//printf(""+scale);

	CSprite@ sprite = this.getSprite();
	if (!this.get_bool("left")) sprite.RotateByDegrees(10, Vec2f(0,0));
	else sprite.RotateByDegrees(-10, Vec2f(0,0));
	if (sprite !is null)
	{
		if (res < 20) 
		{
			sprite.ScaleBy(Vec2f(1.0f+scale, 1.0f+scale));
		}
		else if (res > 25)
		{
			sprite.ScaleBy(Vec2f(1.0f-0.025, 1.0f-0.025));
		}
	}

	Vec2f dir = this.getPosition()-this.get_Vec2f("target");
	dir.Normalize();
	this.setPosition(this.getPosition() + -dir*this.get_f32("vel"));
}

void mortar(CBlob@ this)
{
	Vec2f pos = this.getPosition();
	CMap@ map = getMap();
	CBlob@[] blobs;
	map.getBlobsInRadius(pos, MORTAR_REACH, @blobs);
	
	if (blobs.length < 2)
		return;
		
	f32 angle = XORRandom(360);

	for (u8 s = 0; s < 12; s++)
	{
		HitInfo@[] hitInfos;
		if (map.getHitInfosFromRay(pos, angle, MORTAR_REACH, this, @hitInfos))
		{
			for (uint i = 0; i < hitInfos.length; i++)//sharpnel trail
			{
				CBlob@ b = hitInfos[i].blob;	  
				if (b is null || b is this) continue;
									
				const bool sameTeam = b.getTeamNum() == this.getTeamNum();
				if (!b.hasTag("seat") && (b.hasTag("block") || b.hasTag("weapon")) && b.getShape().getVars().customData > 0 && !sameTeam)
				{
					this.server_Hit(b, hitInfos[i].hitpos, Vec2f_zero, getDamage(b), Hitters::bomb, true);
				}
			}
		}
		
		angle = (angle + 30.0f) % 360;
	}
}

void onDie(CBlob@ this)
{
	Vec2f pos = this.getPosition();
	bool hitwater = isInWater(pos);

	CBlob@[] tiles;
	if (getMap() !is null && getMap().getBlobsAtPosition(pos, @tiles))
	{
		for (u8 i = 0; i < tiles.length; i++)
		{
			if (tiles[i] !is null && tiles[i].hasTag("block"))
			{
				hitwater = false;
				break;
			}
		}
	}

	if (isClient())
	{
		if (hitwater)
		{
			MakeWaterParticle(pos, Vec2f_zero);
			directionalSoundPlay("WaterSplashBall.ogg", pos);
		}
		else
		{
			directionalSoundPlay("FlakExp"+XORRandom(2), pos, 2.5f);
			for (u8 i = 0; i < (v_fastrender ? 1 : 3); i++)
			{
				makeLargeExplosionParticle(pos + getRandomVelocity(90, 12, 360));
			}
		}
	}

	if (isServer() && !hitwater)
	{
		//splash damage
		CBlob@[] blobsInRadius;
		if (getMap().getBlobsInRadius(pos, SPLASH_RADIUS, @blobsInRadius))
		{
			const u8 blobsLength = blobsInRadius.length;
			for (u8 i = 0; i < blobsLength; i++)
			{
				CBlob@ b = blobsInRadius[i];
				if (!b.hasTag("hasSeat") && !b.hasTag("mothership") && b.hasTag("block") && b.getShape().getVars().customData > 0)
					this.server_Hit(b, Vec2f_zero, Vec2f_zero, getDamage(b) * SPLASH_DAMAGE, Hitters::explosion, false);
			}
		}
	}
}

void onHitBlob(CBlob@ this, Vec2f worldPoint, Vec2f velocity, f32 damage, CBlob@ hitBlob, u8 customData)
{
	CPlayer@ owner = this.getDamageOwnerPlayer();
	if (owner !is null)
	{
		CBlob@ blob = owner.getBlob();
		if (blob !is null)
			rewardBooty(owner, hitBlob, booty_reward);
	}
}

void Explode(CBlob@ this, f32 radius = EXPLODE_RADIUS)
{
    Vec2f pos = this.getPosition();

	directionalSoundPlay("Bomb.ogg", pos);
    makeLargeExplosionParticle(pos);
    ShakeScreen(4*radius, 45, pos);

	//hit blobs
	CBlob@[] blobs;
	getMap().getBlobsInRadius(pos, radius, @blobs);

	for (uint i = 0; i < blobs.length; i++)
	{
		CBlob@ hit_blob = blobs[i];
		if (hit_blob is this)
			continue;

		if (isServer())
		{
			Vec2f hit_blob_pos = hit_blob.getPosition();  

			//hit the object
			this.server_Hit(hit_blob, hit_blob_pos, Vec2f_zero, getDamage(hit_blob), Hitters::explosion, true);
		}
	}
}

f32 getDamage(CBlob@ hitBlob)
{
	if (hitBlob.hasTag("bomb"))
		return 4.0f;
	if (hitBlob.hasTag("ram"))
		return 0.5f;
	if (hitBlob.hasTag("propeller"))
		return 0.5f;
	if (hitBlob.hasTag("antiram"))
		return 1.0f;
	if (hitBlob.hasTag("ramengine"))
		return 0.75f;
	if (hitBlob.hasTag("door") || hitBlob.hasTag("weapon"))
		return 0.33f;
	if (hitBlob.getName() == "shark" || hitBlob.getName() == "human")
		return 1.0f;
	if (hitBlob.hasTag("seat"))
		return 0.1f;
	if (hitBlob.hasTag("mothership") || hitBlob.hasTag("secondaryCore"))
		return 0.5f;
	if (hitBlob.hasTag("decoycore"))
		return 0.3f;
	
	return 0.35f;
}