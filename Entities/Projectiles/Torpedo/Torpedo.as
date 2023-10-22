#include "DamageBooty.as";
#include "AccurateSoundPlay.as";
#include "ParticleSpark.as";
#include "Hitters.as";
#include "PlankCommon.as";
#include "WaterEffects.as";

const f32 SPLASH_RADIUS = 20.0f;
const f32 SPLASH_DAMAGE = 1.5f;
//const f32 MANUAL_DAMAGE_MODIFIER = 0.75f;

const f32 TORPEDO_FORCE = 4.0f;
const int TORPEDO_DELAY = 15;
const f32 ROTATION_SPEED = 1.5f;

Random _effectspreadrandom(0x11598); //clientside

BootyRewards@ booty_reward;

void onInit(CBlob@ this)
{
	if (booty_reward is null)
	{
		BootyRewards _booty_reward;
		_booty_reward.addTagReward("bomb", 25);
		_booty_reward.addTagReward("engine", 20);
		_booty_reward.addTagReward("mothership", 50);
		_booty_reward.addTagReward("secondarycore", 30);
		_booty_reward.addTagReward("weapon", 25);
		_booty_reward.addTagReward("solid", 20);
		@booty_reward = _booty_reward;
	}
	
	this.Tag("projectile"); // enables AA trigger
	this.Tag("torpedo");
	
	this.set_f32("camera_angle", this.getAngleDegrees());
	this.set_f32("camera_rotation", this.getAngleDegrees());
	this.SetMapEdgeFlags(CBlob::map_collide_none);

	ShapeConsts@ consts = this.getShape().getConsts();
    consts.mapCollisions = true;
	consts.bullet = true;	

	if (isClient())
	{
		if (this.getPlayer() !is null && this.getPlayer().isMyPlayer() && getCamera() !is null)
			getCamera().setRotation(this.getAngleDegrees());

		CSprite@ sprite = this.getSprite();
		sprite.SetZ(1.5f);	
		sprite.SetEmitSound("/torpedo_loop.ogg");
		sprite.SetEmitSoundVolume(0.4f);
		sprite.SetEmitSoundSpeed(0.8f);
		sprite.SetEmitSoundPaused(true);
	}

	this.set_u32("last smoke puff", 0);
	this.server_SetTimeToDie(30.0f);
}

Random _anglerandom(0x9090); //clientside

void onTick(CBlob@ this)
{
	if (this.getTimeToDie() <= 0.1f)
	{
		this.Tag("sunk");
		this.server_Die();
	}

	if (this.getPlayer() is null && !this.hasTag("had_shooter"))
	{
		if (isServer() && this.getDamageOwnerPlayer() !is null)
		{
			this.server_SetPlayer(this.getDamageOwnerPlayer());
		}
	}
	else this.Tag("had_shooter");

	Vec2f pos = this.getPosition();
	const f32 angle = this.getAngleDegrees();
	Vec2f aimvector = Vec2f(1,0).RotateBy(angle - 90.0f);
	
	CPlayer@ owner = this.getPlayer();
	if (owner !is null)
	{
		if (this.getTickSinceCreated() > TORPEDO_DELAY)
		{
			f32 thisAngle = this.getAngleDegrees();
			if (this.isKeyPressed(key_action1))
			{
				this.setAngleDegrees(thisAngle - ROTATION_SPEED);
			}
			if (this.isKeyPressed(key_action2))
			{
				this.setAngleDegrees(thisAngle + ROTATION_SPEED);
			}
		}
		else if (owner.isMyPlayer() && getCamera() !is null)
		{
			getCamera().setRotation(this.getAngleDegrees());
		}
	}

	CMap@ map = getMap();
	if (map !is null)
	{
		TileType t = map.getTile(pos).type;
		if (t != 0) // water
		{
			ResetPlayer(this);
			this.server_Die();
		}

		f32 mw = map.tilemapwidth*8;
		f32 mh = map.tilemapheight*8;
		if (pos.x < 12.0f || pos.y < 12.0f || pos.x > mw-12.0f || pos.y > mh-12.0f)
			ResetPlayer(this);
	}

	if (isServer() && this.exists("shooter_id"))
	{
		CBlob@ b = getBlobByNetworkID(this.get_u16("shooter_id"));
		if (b is null)
		{
			if (this.getPlayer() !is null) this.getPlayer().client_RequestSpawn();
			this.server_SetPlayer(null);
		}
		else if (this.getTimeToDie() < 1.0f)
			ResetPlayer(this);
	}
	
	if (this.getTickSinceCreated() > TORPEDO_DELAY)
	{
		//torpedo code!
		this.AddForce(aimvector*TORPEDO_FORCE);
		
		if (isClient())
		{
			CSprite@ sprite = this.getSprite();
			if (sprite.getEmitSoundPaused())
			{
				sprite.SetEmitSoundPaused(false);
			}
			
			f32 fireRandomOffsetX = (_effectspreadrandom.NextFloat() - 0.5) * 3.0f;
			
			const u32 gametime = getGameTime();
			u32 lastSmokeTime = this.get_u32("last smoke puff");
			const int ticksTillSmoke = v_fastrender ? 5 : 2;
			const int diff = gametime - (lastSmokeTime + ticksTillSmoke);

			if ((getGameTime() + this.getNetworkID()) % (v_fastrender ? 7 : 4) == 0)
			{
				MakeWaterWave(pos, Vec2f_zero, -this.getVelocity().Angle() + (_anglerandom.NextRanged(100) > 50 ? 180 : 0)); 
			}

			if (diff > 0)
			{
				MakeWaterParticle(this.getPosition()+Vec2f(0,8).RotateBy(this.getAngleDegrees()), Vec2f_zero);
				lastSmokeTime = gametime;
				this.set_u32("last smoke puff", lastSmokeTime);
			}
		}
	}
}

void onRender(CSprite@ sprite)
{
	CBlob@ this = sprite.getBlob();
	if (this is null) return;

	if (!this.hasTag("had_shooter")) return;

	if (this.getPlayer() !is null && this.getPlayer().isMyPlayer())
	{
		CCamera@ camera = getCamera();
		if (camera !is null)
		{
			f32 next_angle = this.getAngleDegrees();

			if (this.getTickSinceCreated() < TORPEDO_DELAY)
			{
				camera.setRotation(next_angle);
			}
			else
			{
				f32 angle = camera.getRotation();
				f32 angle_delta = next_angle - angle;
				if (angle_delta > 180.0f) angle += 360.0f;
				if (angle_delta < -180.0f) angle -= 360.0f;
			
				camera.setRotation(Maths::Lerp(angle, next_angle, getRenderApproximateCorrectionFactor()));
				this.set_f32("camera_rotation", camera.getRotation());
			}
		}
	}
}


void onCollision(CBlob@ this, CBlob@ b, bool solid, Vec2f normal, Vec2f point1)
{
	if (b is null) //solid tile collision
	{
		if (isClient())
			sparks(point1, v_fastrender ? 5 : 15, 5.0f, 20);
		
		ResetPlayer(this);

		this.server_Die();
		return;
	}
	
	if (!isServer() || this.getTickSinceCreated() <= 4) return;


	bool killed = false;
	
	const int color = b.getShape().getVars().customData;
	const bool isBlock = b.hasTag("block");
	const bool sameTeam = b.getTeamNum() == this.getTeamNum();
	
	if ((b.hasTag("human") || b.hasTag("shark")) && !sameTeam)
	{
		killed = true;
		b.server_Die();
	}
	
	if (color > 0 || !isBlock)
	{
		if (isBlock || b.hasTag("torpedo"))
		{
			if (b.hasTag("solid") || b.hasTag("platform") || b.hasTag("door") ||
				(!sameTeam && (b.hasTag("weapon") || b.hasTag("torpedo") || b.hasTag("bomb") || b.hasTag("core"))))
				killed = true;
			else if (b.hasTag("hasSeat") && !sameTeam)
			{
				AttachmentPoint@ seat = b.getAttachmentPoint(0);
				CBlob@ occupier = seat.getOccupied();
				if (occupier !is null && occupier.getName() == "human" && occupier.getTeamNum() != this.getTeamNum())
					killed = true;
			}
			else return;
		}
		else
		{
			if (sameTeam || (b.hasTag("player") && b.isAttached()) || b.hasTag("projectile")) //don't hit
				return;
		}
	
		if (killed)
		{
			this.Tag("killedTorpedo"); //for instances of multiple collisions on same tick
			ResetPlayer(this);

			this.server_Die();
		}
	}
}

f32 getDamage(CBlob@ hitBlob)
{
	if (hitBlob.hasTag("torpedo"))
		return 4.0f;
	if (hitBlob.hasTag("core"))
		return 3.5f;
	if (hitBlob.hasTag("ramengine"))
		return 5.0f;
	if (hitBlob.hasTag("propeller") || hitBlob.hasTag("plank"))
		return 3.0f;
	if (hitBlob.hasTag("seat") || hitBlob.hasTag("weapon"))
		return 2.5f;
	if (hitBlob.hasTag("decoyCore"))
		return 1.5f;
	

	return 1.4f; //solids
}

void onHitBlob(CBlob@ this, Vec2f worldPoint, Vec2f velocity, f32 damage, CBlob@ hitBlob, u8 customData)
{
	CPlayer@ owner = this.getDamageOwnerPlayer();
	if (owner !is null && customData != Hitters::explosion) //no splash damage included
	{
		rewardBooty(owner, hitBlob, booty_reward);
	}

	ResetPlayer(this);
		
	if (!isClient()) return;
	
	if (customData == 9) return;

	if (hitBlob.hasTag("solid") || hitBlob.hasTag("core") || 
			 hitBlob.hasTag("seat") || hitBlob.hasTag("door") || hitBlob.hasTag("weapon"))
	{
		sparks(worldPoint, v_fastrender ? 5 : 15, 5.0f, 20);
			
		if (hitBlob.hasTag("core"))
			directionalSoundPlay("Entities/Characters/Knight/ShieldHit.ogg", worldPoint);
		else
			directionalSoundPlay("Blast1.ogg", worldPoint);
	}
}

f32 onHit(CBlob@ this, Vec2f worldPoint, Vec2f velocity, f32 damage, CBlob@ hitterBlob, u8 customData)
{
	if (this.getHealth() - damage <= 0.0f)
		ResetPlayer(this);

	return damage;
}

void ResetPlayer(CBlob@ this)
{
	if (isServer())
	{
		if (this.exists("shooter_id") && this.getPlayer() !is null)
		{
			CBlob@ oldblob = getBlobByNetworkID(this.get_u16("shooter_id"));
			if (oldblob !is null)
			{
				oldblob.server_SetPlayer(this.getPlayer());
			}
			else
			{
				if (this.getPlayer() !is null) this.getPlayer().client_RequestSpawn();
				this.server_SetPlayer(null);
			}
		}
	}
}

void onDie(CBlob@ this)
{
	ResetPlayer(this);
	Vec2f pos = this.getPosition();

	if (this.hasTag("sunk"))
	{
		if (isClient())
		{
			if (!isInWater(pos))
			{
				sparks(pos + this.getVelocity(), v_fastrender ? 5 : 15, 2.5, 20);
				directionalSoundPlay("MetalImpact" + (XORRandom(2) + 1), pos);
			}
			else if (this.getTouchingCount() <= 0)
			{
				MakeWaterParticle(pos, Vec2f_zero);
				directionalSoundPlay("WaterSplashBall.ogg", pos);
			}
		}
		
		return;
	}

	if (isClient())
	{
		smoke(pos, v_fastrender ? 1 : 3);	
		blast(pos, v_fastrender ? 1 : 3);															
		directionalSoundPlay("Blast2.ogg", pos);
	}

	if (isServer())
	{
		//splash damage
		CBlob@[] blobsInRadius;
		if (getMap().getBlobsInRadius(pos, SPLASH_RADIUS, @blobsInRadius))
		{
			const u8 blobsLength = blobsInRadius.length;
			for (u8 i = 0; i < blobsLength; i++)
			{
				CBlob@ b = blobsInRadius[i];
				if (b.hasTag("block") && b.getShape().getVars().customData > 0)
					this.server_Hit(b, Vec2f_zero, Vec2f_zero, getDamage(b) * SPLASH_DAMAGE, Hitters::explosion, false);
			}
		}
	}
}

Random _smoke_r(0x10001);
void smoke(const Vec2f pos, const u8 amount)
{
	for (u8 i = 0; i < amount; i++)
    {
        Vec2f vel(2.0f + _smoke_r.NextFloat() * 2.0f, 0);
        vel.RotateBy(_smoke_r.NextFloat() * 360.0f);

        CParticle@ p = ParticleAnimated(CFileMatcher("GenericSmoke3.png").getFirst(), 
									pos, 
									vel, 
									float(XORRandom(360)), 
									1.0f, 
									4 + XORRandom(8), 
									0.0f, 
									false);
									
        if (p is null) return; //bail if we stop getting particles
		
        p.scale = 0.5f + _smoke_r.NextFloat()*0.5f;
        p.damping = 0.8f;
		p.Z = 650.0f;
    }
}

Random _blast_r(0x10002);
void blast(const Vec2f pos, const u8 amount)
{
	for (u8 i = 0; i < amount; i++)
    {
        Vec2f vel(_blast_r.NextFloat() * 2.5f, 0);
        vel.RotateBy(_blast_r.NextFloat() * 360.0f);

        CParticle@ p = ParticleAnimated(CFileMatcher("GenericBlast6.png").getFirst(), 
									pos, 
									vel, 
									float(XORRandom(360)), 
									1.0f, 
									2 + XORRandom(4), 
									0.0f, 
									false);
									
        if (p is null) return; //bail if we stop getting particles
		
        p.scale = 0.5f + _blast_r.NextFloat()*0.5f;
        p.damping = 0.85f;
		p.Z = 650.0f;
    }
}
